-- test_notify_focus.lua
-- Offline regressions for notify-focus.lua: pairing DMS notification clicks with kitty's
-- urgent events. Pure Lua, no hyprctl. Run: lua5.5 .config/hypr/tests/test_notify_focus.lua

local dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local path = os.getenv("NOTIFY_FOCUS") or (dir .. "/../notify-focus.lua")
local M = assert(loadfile(path))()

-- Virtual compositor: a clock, windows by address, the focused address and a timer queue.
local function world()
    local w = { t = 1000, windows = {}, active = nil, calls = {}, timers = {}, logs = {}, handlers = {} }
    w.be = {
        now = function() return w.t end,
        get_window = function(a) return w.windows[a] end,
        active_window = function() return w.active and w.windows[w.active] or nil end,
        focus = function(a) w.calls[#w.calls + 1] = "focus " .. a; w.active = a end,
        raise = function(a) w.calls[#w.calls + 1] = "raise " .. a end,
        after = function(ms, cb) w.timers[#w.timers + 1] = { at = w.t + ms, cb = cb } end,
        on = function(ev, cb) w.handlers[ev] = cb end,
        log = function(s) w.logs[#w.logs + 1] = s end,
    }
    function w.add(addr, class, floating)
        w.windows[addr] = { address = addr, class = class, floating = floating }
        return w.windows[addr]
    end
    function w.advance(ms)
        local target = w.t + ms
        while true do
            local idx
            for i, tm in ipairs(w.timers) do
                if tm.at <= target and (not idx or tm.at < w.timers[idx].at) then idx = i end
            end
            if not idx then break end
            local tm = table.remove(w.timers, idx)
            w.t = tm.at
            tm.cb()
        end
        w.t = target
    end
    return w
end

local function calls(w) return table.concat(w.calls, ", ") end

local cases, failed = 0, 0
local function case(name, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function eq(got, want, what)
    if got ~= want then error(string.format("%s: got %q, want %q", what or "value", tostring(got), tostring(want)), 2) end
end

case("click then urgent focuses and raises a floating kitty window", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xb", "firefox", true); w.active = "0xb"
    nf.clicked("kitty"); w.advance(60); nf.urgent(w.windows["0xa"])
    eq(calls(w), "focus 0xa, raise 0xa", "calls")
    w.advance(2000)
    eq(calls(w), "focus 0xa, raise 0xa", "fallback cancelled")
end)

case("urgent then click focuses and raises", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true)
    nf.urgent(w.windows["0xa"]); w.advance(30); nf.clicked("kitty")
    eq(calls(w), "focus 0xa, raise 0xa", "calls")
    w.advance(2000)
    eq(calls(w), "focus 0xa, raise 0xa", "no fallback after pairing")
end)

case("tiled kitty window is focused without a z-order change", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", false)
    nf.clicked("kitty"); nf.urgent(w.windows["0xa"])
    eq(calls(w), "focus 0xa", "calls")
end)

case("urgent with no click (a bell) is ignored", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true)
    nf.urgent(w.windows["0xa"]); w.advance(5000)
    eq(calls(w), "", "calls")
end)

case("a bell long before a click is not paired", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xb", "firefox", true); w.active = "0xb"
    nf.urgent(w.windows["0xa"]); w.advance(1600); nf.clicked("kitty"); w.advance(2000)
    eq(calls(w), "", "calls")
end)

case("urgent arriving after the pairing window is ignored", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xb", "firefox", true); w.active = "0xb"
    nf.clicked("kitty"); w.advance(1600); nf.urgent(w.windows["0xa"])
    eq(calls(w), "", "calls")
end)

case("click on the already focused kitty window raises it after the fallback", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.active = "0xa"
    nf.clicked("kitty"); w.advance(399)
    eq(calls(w), "", "not before the fallback")
    w.advance(1)
    eq(calls(w), "raise 0xa", "calls")
end)

case("fallback leaves a focused non-kitty window alone", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xb", "firefox", true); w.active = "0xb"
    nf.clicked("kitty"); w.advance(2000)
    eq(calls(w), "", "calls")
end)

case("fallback leaves a focused tiled kitty window alone", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", false); w.active = "0xa"
    nf.clicked("kitty"); w.advance(2000)
    eq(calls(w), "", "calls")
end)

case("slow activation after the fallback still focuses the sender", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xc", "kitty", true); w.active = "0xa"
    nf.clicked("kitty"); w.advance(700); nf.urgent(w.windows["0xc"])
    eq(calls(w), "raise 0xa, focus 0xc, raise 0xc", "calls")
end)

case("clicks on other apps' notifications are ignored", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.active = "0xa"
    nf.clicked("ChatGPT"); w.advance(10); nf.urgent(w.windows["0xa"]); w.advance(2000)
    eq(calls(w), "", "calls")
end)

case("app name match is case-insensitive and an empty name is accepted", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true)
    nf.clicked("Kitty"); nf.urgent(w.windows["0xa"])
    nf.clicked(""); w.advance(10); nf.urgent(w.windows["0xa"])
    eq(calls(w), "focus 0xa, raise 0xa, focus 0xa, raise 0xa", "calls")
end)

case("urgent from another class does not consume the click", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xd", "discord", false)
    nf.clicked("kitty"); nf.urgent(w.windows["0xd"]); w.advance(20); nf.urgent(w.windows["0xa"])
    eq(calls(w), "focus 0xa, raise 0xa", "calls")
end)

case("one click brings forward one window", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xc", "kitty", true)
    nf.clicked("kitty"); nf.urgent(w.windows["0xa"]); w.advance(50); nf.urgent(w.windows["0xc"])
    eq(calls(w), "focus 0xa, raise 0xa", "calls")
end)

case("a window that closed between urgent and click is skipped", function()
    local w = world(); local nf = M.new(w.be)
    w.add("0xa", "kitty", true); w.add("0xb", "firefox", true); w.active = "0xb"
    nf.urgent(w.windows["0xa"]); w.windows["0xa"] = nil; nf.clicked("kitty"); w.advance(2000)
    eq(calls(w), "", "calls")
end)

case("floating state is re-read when the click pairs a stored urgent event", function()
    local w = world(); local nf = M.new(w.be)
    local win = w.add("0xa", "kitty", true)
    nf.urgent({ address = "0xa", class = "kitty", floating = true })
    win.floating = false
    nf.clicked("kitty")
    eq(calls(w), "focus 0xa", "calls")
end)

case("unreadable payloads and a missing clock are ignored", function()
    local w = world(); local nf = M.new(w.be)
    local bad = setmetatable({}, { __index = function() error("stale window") end })
    nf.clicked("kitty"); nf.urgent(bad); nf.urgent(nil); nf.urgent({ class = "kitty" })
    eq(calls(w), "", "calls")
    w.be.now = function() return nil end
    w.add("0xa", "kitty", true)
    nf.clicked("kitty"); nf.urgent(w.windows["0xa"])
    eq(calls(w), "", "no clock, no action")
end)

case("setup wires window.urgent and the notify_focus global, and contains faults", function()
    local w = world()
    _G.notify_focus = nil
    M.setup(w.be)
    assert(w.handlers["window.urgent"], "urgent handler registered")
    assert(type(notify_focus) == "table" and type(notify_focus.clicked) == "function", "global exposed")
    w.add("0xa", "kitty", true)
    notify_focus.clicked("kitty"); w.handlers["window.urgent"](w.windows["0xa"])
    eq(calls(w), "focus 0xa, raise 0xa", "calls")
    w.be.focus = function() error("dispatch failed") end
    notify_focus.clicked("kitty"); w.handlers["window.urgent"](w.windows["0xa"])
    eq(#w.logs, 1, "fault logged")
    assert(w.logs[1]:find("dispatch failed", 1, true), "log names the fault")
    _G.notify_focus = nil
end)

-- Fake hl for the real backend: records config writes and what no_warps held at dispatch.
local function fake_hl(no_warps, dispatch_error)
    local h = { cfg = { ["cursor:no_warps"] = no_warps }, log = {} }
    h.get_config = function(k) return h.cfg[k] end
    h.config = function(t)
        for section, kv in pairs(t) do
            for k, v in pairs(kv) do
                h.cfg[section .. ":" .. k] = v
                h.log[#h.log + 1] = section .. ":" .. k .. "=" .. tostring(v)
            end
        end
    end
    h.dsp = {
        focus = function(spec) return { kind = "focus", window = spec.window } end,
        window = { alter_zorder = function(spec) return { kind = "zorder", window = spec.window } end },
    }
    h.dispatch = function(d)
        h.log[#h.log + 1] = d.kind .. " " .. d.window .. " no_warps=" .. tostring(h.cfg["cursor:no_warps"])
        if dispatch_error and d.kind == "focus" then error(dispatch_error) end
    end
    return h
end

case("backend focus never warps the pointer and restores no_warps", function()
    _G.hl = fake_hl(false)
    M.hyprland_backend().focus("0xa")
    eq(table.concat(hl.log, ", "), "cursor:no_warps=true, focus address:0xa no_warps=true, cursor:no_warps=false", "log")
    _G.hl = fake_hl(true)
    M.hyprland_backend().focus("0xa")
    eq(hl.cfg["cursor:no_warps"], true, "a configured no_warps stays on")
    _G.hl = fake_hl(1)
    M.hyprland_backend().focus("0xa")
    eq(hl.cfg["cursor:no_warps"], true, "numeric no_warps read as on")
end)

case("backend restores no_warps even when the dispatch fails", function()
    _G.hl = fake_hl(false, "window not found")
    local ok, err = pcall(M.hyprland_backend().focus, "0xa")
    eq(ok, false, "error propagates")
    assert(tostring(err):find("window not found", 1, true), "error message kept")
    eq(hl.cfg["cursor:no_warps"], false, "restored")
end)

case("backend raise does not touch no_warps", function()
    _G.hl = fake_hl(false)
    M.hyprland_backend().raise("0xa")
    eq(table.concat(hl.log, ", "), "zorder address:0xa no_warps=false", "log")
    _G.hl = nil
end)

print(string.format("notify-focus: %d/%d cases passed", cases - failed, cases))
if failed > 0 then os.exit(1) end
