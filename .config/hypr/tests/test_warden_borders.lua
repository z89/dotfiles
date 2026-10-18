-- test_warden_borders.lua
-- Offline regressions for warden-borders.lua: boxed session windows get the accent border.
-- Pure Lua, no hyprctl. Run: lua5.5 .config/hypr/tests/test_warden_borders.lua

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local M = assert(loadfile(os.getenv("WARDEN_BORDERS") or (dir .. "/../warden-borders.lua")))()

local COLOURS = [[
hl.config({
	general = {
		col = {
			active_border = "rgb(b2d400)",
			inactive_border = "rgb(969885)",
		},
	},
})
]]

local NEUTRAL = "gradient 0xFFE7E8D3 0deg gradient 0xFF636655 0deg"

local function world()
    local w = { windows = {}, calls = {}, handlers = {}, logs = {}, file = COLOURS,
                neutral = { "gradient 0xFFE7E8D3 0deg", "gradient 0xFF636655 0deg" } }
    w.be = {
        read = function() return w.file end,
        windows = function()
            local list = {}
            for _, win in pairs(w.windows) do list[#list + 1] = win end
            table.sort(list, function(a, b) return a.address < b.address end)
            return list
        end,
        set = function(addr, active, inactive)
            w.calls[#w.calls + 1] = addr .. " " .. tostring(active) .. " " .. tostring(inactive)
        end,
        neutral = function() return w.neutral[1], w.neutral[2] end,
        tag = function(addr, tag)
            local win = w.windows[addr]
            if win and tag:sub(1, 1) == "+" then
                win.tags = win.tags or {}
                win.tags[#win.tags + 1] = tag:sub(2)
            end
        end,
        on = function(ev, cb)
            w.handlers[ev] = cb
            return { remove = function() if w.handlers[ev] == cb then w.handlers[ev] = nil end end }
        end,
        log = function(s) w.logs[#w.logs + 1] = s end,
    }
    function w.add(addr, title)
        w.windows[addr] = { address = addr, title = title }
        return w.windows[addr]
    end
    return w
end

local passed = 0
local function check(name, got, want)
    if got ~= want then
        error(("%s: got %s, want %s"):format(name, tostring(got), tostring(want)), 2)
    end
    passed = passed + 1
end

-- the accent comes from the general active_border, not the group colours
check("accent", M.accent(COLOURS), "b2d400")
check("no accent", M.accent("nothing here"), nil)
check("no file", M.accent(nil), nil)

-- the live general gradient becomes a set_prop value led by the placeholder word
check("one colour", M.colour({ colors = { "0xFFE7E8D3" }, angle = 0 }), "gradient 0xFFE7E8D3 0deg")
check("gradient", M.colour({ colors = { "0xFF000000", "0xFFFFFFFF" }, angle = 45.0 }), "gradient 0xFF000000 0xFFFFFFFF 45deg")
check("no colours", M.colour({ colors = {} }), nil)
check("no gradient", M.colour(nil), nil)
check("tag string", M.tagged({ tags = "warden-border" }), true)
check("no tags", M.tagged({}), false)

do -- setup paints windows that are already open, and only boxed ones
    local w = world()
    w.add("0xa", "\u{1F512} z89 \u{00B7} Claude Code")
    w.add("0xb", "zsh")
    M.setup(w.be)
    check("setup paints", #w.calls, 1)
    check("setup colours", w.calls[1], "0xa rgb(b2d400) rgba(b2d40099)")
    check("global", type(_G.warden_borders.refresh), "function")
end

do -- a title change marks and unmarks a window
    local w = world()
    M.setup(w.be)
    local win = w.add("0xc", "zsh")
    w.handlers["window.open"](win)
    check("plain window untouched", #w.calls, 0)
    win.title = "\u{1F512} work \u{00B7} opencode"
    w.handlers["window.title"](win)
    check("marked", w.calls[1], "0xc rgb(b2d400) rgba(b2d40099)")
    win.title = "~/Documents"
    w.handlers["window.title"](win)
    check("neutral after the session", w.calls[2], "0xc " .. NEUTRAL)
    w.handlers["window.title"](win)
    check("restored once", #w.calls, 2)
    check("tagged once", #win.tags, 1)
end

do -- a window whose session ended follows the theme, also after a reload forgot it
    local w = world()
    local win = w.add("0x11", "\u{1F512} z89")
    M.setup(w.be)
    win.title = "zsh"
    w.handlers["window.title"](win)
    M.setup(w.be) -- a reload: the new instance only has the tag to go by
    w.neutral = { "gradient 0xFF111111 0deg", "gradient 0xFF222222 0deg" }
    _G.warden_borders.refresh()
    check("follows the theme", w.calls[#w.calls], "0x11 gradient 0xFF111111 0deg gradient 0xFF222222 0deg")
    w.add("0x12", "zsh")
    local before = #w.calls
    _G.warden_borders.refresh()
    check("untagged left alone", #w.calls, before + 1)
end

do -- without the live colours the accent stays rather than clearing the border
    local w = world()
    local win = w.add("0x13", "\u{1F512} z89")
    M.setup(w.be)
    w.neutral = {}
    win.title = "zsh"
    w.handlers["window.title"](win)
    check("no neutral, no set", #w.calls, 1)
    w.neutral = { "a", "b" }
    w.handlers["window.title"](win)
    check("restored later", w.calls[2], "0x13 a b")
end

do -- a theme change repaints every boxed window with the new accent
    local w = world()
    w.add("0xd", "\u{1F512} z89")
    M.setup(w.be)
    w.file = COLOURS:gsub("b2d400", "ff8800", 1)
    _G.warden_borders.refresh()
    check("refreshed", w.calls[#w.calls], "0xd rgb(ff8800) rgba(ff880099)")
end

do -- a lock later in the title is not a boxed window
    check("lock inside", M.boxed({ title = "notes about \u{1F512}" }), false)
    check("no title", M.boxed({}), false)
end

do -- an unreadable colour file leaves windows alone, and a fault is logged, not raised
    local w = world()
    w.file = nil
    w.add("0xe", "\u{1F512} z89")
    M.setup(w.be)
    check("no colours, no paint", #w.calls, 0)
    w.be.set = function() error("dispatch failed") end
    w.file = COLOURS
    _G.warden_borders.refresh()
    check("fault logged", w.logs[1]:match("^warden%-borders: ") ~= nil, true)
end

do -- a destroyed window is forgotten
    local w = world()
    M.setup(w.be)
    local win = w.add("0xf", "\u{1F512} z89")
    w.handlers["window.open"](win)
    w.handlers["window.destroy"](win)
    win.title = "zsh"
    w.handlers["window.title"](win)
    check("no clear after destroy", #w.calls, 1)
end

do -- stop removes the handlers and gives the borders back, a second setup stops the first
    local w = world()
    w.add("0x10", "\u{1F512} z89")
    M.setup(w.be)
    M.setup(w.be)
    check("second setup clears the first", w.calls[2], "0x10 " .. NEUTRAL)
    check("and paints again", w.calls[3], "0x10 rgb(b2d400) rgba(b2d40099)")
    _G.warden_borders.stop()
    check("stop clears", w.calls[4], "0x10 " .. NEUTRAL)
    check("handlers gone", w.handlers["window.title"], nil)
    check("global gone", _G.warden_borders, nil)
end

print(("test_warden_borders: %d checks passed"):format(passed))
