-- warden-borders: windows running a boxed agent session get their own border colour.
--
-- warden's terminal relay puts a lock and the profile in front of every window title a
-- boxed session sets ("🔒 z89 · <title>"). This module watches window titles and gives a
-- window whose title starts with the lock the wallpaper accent as its border: the accent
-- itself when focused, the accent at 60% when not. Every other window keeps the neutral
-- borders from borders.lua. Hyprland 0.56 has no way to clear a border colour set_prop
-- ("unset" leaves the window with no border at all), so a window whose session ended is
-- painted with the live general colours instead. Each painted window also gets the static
-- warden-border tag, and every refresh repaints tagged windows, so they keep following the
-- theme after a session ends and across a config reload. The accent is DMS's matugen primary, read from dms/colors.lua,
-- so it follows the theme switcher. theme-apply calls warden_borders.refresh() over
-- `hyprctl eval` when it fades the borders, and the boxed windows fade with them.
--
-- The lock is a cue, not a proof: any program running as the operator can set such a title,
-- and so can a web page, through a browser tab title.
-- kitty shows the active tab's title, so a boxed session in a background tab is not marked.
--
-- Loaded from hyprland.lua with io + load, so it is not watched: a change here needs a config
-- reload.
-- Offline tests: .config/hypr/tests/test_warden_borders.lua.

local M = {}

M.MARK    = "\u{1F512}"
M.COLOURS = (os.getenv("HOME") or "") .. "/.config/hypr/dms/colors.lua"
M.DIM     = "99" -- alpha of the unfocused border
M.TAG     = "warden-border"

-- The first general active_border hex in the DMS colour file, the matugen primary.
function M.accent(text)
    return text and text:match('active_border%s*=%s*"rgb%((%x%x%x%x%x%x)%)"')
end

function M.boxed(window)
    return (window.title or ""):sub(1, #M.MARK) == M.MARK
end

function M.tagged(window)
    local tags = window.tags
    if type(tags) == "string" then tags = { tags } end
    for _, t in ipairs(tags or {}) do
        if t == M.TAG or t == M.TAG .. "*" then return true end
    end
    return false
end

-- A set_prop value for the gradient hl.get_config returns ({ colors = { "0xAARRGGBB" }, angle }).
-- set_prop skips the first word of a value with several words, so it leads with a placeholder,
-- which parses as no colour if a later release reads it after all.
function M.colour(gradient)
    if type(gradient) == "string" then return gradient end
    if type(gradient) ~= "table" or type(gradient.colors) ~= "table" or #gradient.colors == 0 then return nil end
    return ("gradient %s %ddeg"):format(table.concat(gradient.colors, " "), math.floor((gradient.angle or 0) + 0.5))
end

function M.new(be)
    local self = { marked = {} }

    -- Gives the window the neutral borders back.
    local function restore(addr)
        local active, inactive = be.neutral()
        if not active or not inactive then return false end
        be.set(addr, active, inactive)
        return true
    end

    -- Colours the window when its title carries the lock and gives the neutral borders back to
    -- one it coloured before. A sweep (refresh) also repaints every tagged window.
    function self.paint(w, sweep)
        if not w or not w.address then return end
        if M.boxed(w) then
            if self.active then
                be.set(w.address, self.active, self.inactive)
                self.marked[w.address] = true
                if not M.tagged(w) then be.tag(w.address, "+" .. M.TAG) end
            end
        elseif self.marked[w.address] or (sweep and M.tagged(w)) then
            if restore(w.address) then self.marked[w.address] = nil end
        end
    end

    -- Rereads the accent and repaints every boxed window.
    function self.refresh()
        local hex = M.accent(be.read(M.COLOURS))
        if hex then
            self.active, self.inactive = "rgb(" .. hex .. ")", "rgba(" .. hex .. M.DIM .. ")"
        end
        for _, w in ipairs(be.windows()) do self.paint(w, true) end
    end

    function self.forget(w)
        if w and w.address then self.marked[w.address] = nil end
    end

    -- Gives every window it coloured its normal borders back.
    function self.clear()
        for addr in pairs(self.marked) do restore(addr) end
        self.marked = {}
    end

    return self
end

function M.hyprland_backend()
    local function set_prop(addr, prop, value)
        hl.dispatch(hl.dsp.window.set_prop({ prop = prop, value = value, window = "address:" .. addr }))
    end
    return {
        read = function(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local text = f:read("*a")
            f:close()
            return text
        end,
        windows = function() return hl.get_windows() or {} end,
        set = function(addr, active, inactive)
            set_prop(addr, "active_border_color", active)
            set_prop(addr, "inactive_border_color", inactive)
        end,
        neutral = function()
            return M.colour(hl.get_config("general.col.active_border")),
                M.colour(hl.get_config("general.col.inactive_border"))
        end,
        tag = function(addr, tag)
            hl.dispatch(hl.dsp.window.tag({ tag = tag, window = "address:" .. addr }))
        end,
        on = function(event, cb) return hl.on(event, cb) end,
        log = print,
    }
end

-- Registers the window handlers and the warden_borders global that `hyprctl eval` reaches.
-- warden_borders.stop() removes the handlers and the colours again without a reload, and a
-- second setup stops the first. Every entry point is guarded so a fault never breaks the config.
function M.setup(be)
    be = be or M.hyprland_backend()
    if _G.warden_borders then pcall(_G.warden_borders.stop) end
    local wb = M.new(be)
    local function guard(fn, arg)
        local ok, err = pcall(fn, arg)
        if not ok then pcall(be.log, "warden-borders: " .. tostring(err)) end
    end
    local subs = {
        be.on("window.open", function(w) guard(wb.paint, w) end),
        be.on("window.title", function(w) guard(wb.paint, w) end),
        be.on("window.destroy", function(w) guard(wb.forget, w) end),
    }
    _G.warden_borders = {
        refresh = function() guard(wb.refresh) end,
        stop = function()
            for _, sub in ipairs(subs) do pcall(function() sub:remove() end) end
            guard(wb.clear)
            _G.warden_borders = nil
        end,
    }
    guard(wb.refresh)
    return wb
end

return M
