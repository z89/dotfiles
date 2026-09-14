-- notify-focus: clicking a notification brings the kitty window that sent it forward.
--
-- The path a click takes. Claude Code posts its notifications through kitty (OSC 99).
-- DMS invokes the notification's action over D-Bus, and kitty asks the compositor to
-- activate the OS window that printed it (xdg-activation). misc.focus_on_activate is
-- off, so bells and background apps cannot steal focus: CWindow::activate marks the
-- window urgent, emits window.urgent, and stops there.
--
-- The patched DMS (dms-shell-patch, "notification click raises the sender") reports
-- every action click first:
--
--   hyprctl eval 'return notify_focus and notify_focus.clicked("kitty")'
--
-- This module pairs that click with the urgent event from a kitty window and focuses
-- it. Hyprland's focus switches to the window's workspace when it is not the active
-- one, and a floating window is lifted to the top of the stack. The click and the
-- urgent event arrive in either order, so each waits PAIR_MS for the other. An urgent
-- event with no click (a bell) is left alone.
--
-- A window that already has focus never goes urgent (kitty does not ask, and
-- CWindow::activate returns early), so when no urgent event has arrived FALLBACK_MS
-- after a click, the focused kitty window is the sender and is only raised. The click
-- stays armed until PAIR_MS for a slow activation from another kitty window.
--
-- Loaded from hyprland.lua with io + load like carry.lua, so it is not watched: a
-- change here needs a config reload. Offline tests: .config/hypr/tests/test_notify_focus.lua.

local M = {}

M.CLASSES     = { kitty = true } -- window classes (and DMS app names) a click may bring forward
M.PAIR_MS     = 1500             -- a click and an urgent event this close together belong together
M.FALLBACK_MS = 400              -- no urgent event by now: the sender already had focus

local function read_uptime_ms()
    local f = io.open("/proc/uptime", "r")
    if not f then return nil end
    local line = f:read("l")
    f:close()
    local v = line and tonumber(line:match("^(%S+)"))
    return v and v * 1000 or nil
end

-- HL.Window is userdata whose __index can raise, so the fields are read once under pcall.
local function read_window(w)
    return { address = w.address, class = w.class, floating = w.floating == true }
end

local function norm(w)
    if w == nil then return nil end
    local ok, t = pcall(read_window, w)
    if ok and type(t.address) == "string" and t.address ~= "" then return t end
    return nil
end

-- be: now() -> ms | nil, get_window(addr), active_window(), focus(addr), raise(addr),
-- after(ms, cb). Addresses are the plain "0x..." form HL.Window.address carries.
function M.new(be, opts)
    opts = opts or {}
    local classes     = opts.classes or M.CLASSES
    local pair_ms     = opts.pair_ms or M.PAIR_MS
    local fallback_ms = opts.fallback_ms or M.FALLBACK_MS

    local click_at        -- uptime ms of the last click no urgent event has claimed
    local click_gen = 0   -- bumped to cancel a pending fallback
    local urgent          -- { address, at } of the last urgent kitty window no click has claimed

    local function wanted(w)
        return w ~= nil and type(w.class) == "string" and classes[w.class] == true
    end

    local function bring(w)
        be.focus(w.address)
        if w.floating then be.raise(w.address) end
    end

    local self = {}

    function self.clicked(app)
        if type(app) == "string" and app ~= "" and not classes[app:lower()] then return end
        local t = be.now()
        if not t then return end

        local u = urgent
        urgent = nil
        if u and t - u.at <= pair_ms then
            -- Read the window again: it may have closed or changed floating state since.
            local w = norm(be.get_window(u.address))
            if wanted(w) then
                click_at = nil
                click_gen = click_gen + 1
                bring(w)
                return
            end
        end

        click_at = t
        click_gen = click_gen + 1
        local gen = click_gen
        be.after(fallback_ms, function()
            if gen ~= click_gen or click_at == nil then return end
            local w = norm(be.active_window())
            if wanted(w) and w.floating then be.raise(w.address) end
        end)
    end

    function self.urgent(raw)
        local w = norm(raw)
        if not wanted(w) then return end
        local t = be.now()
        if not t then return end

        if click_at and t - click_at <= pair_ms then
            click_at = nil
            click_gen = click_gen + 1
            bring(w)
            return
        end
        click_at = nil
        urgent = { address = w.address, at = t }
    end

    return self
end

-- Focusing a window ends in CWindow::warpCursor, which moves the pointer to the window
-- unless cursor:no_warps is set (CPointerController::warpTo). The pointer must stay where
-- the user left it, so no_warps is forced on for this one synchronous dispatch and the
-- previous value put back, leaving every other focus bind's warping as configured. The
-- workspace switch inside the focus does not warp (cursor:warp_on_change_workspace is 0)
-- and alter_zorder never does.
local function focus_without_warp(selector)
    local prev = hl.get_config("cursor:no_warps")
    prev = prev == true or prev == 1
    hl.config({ cursor = { no_warps = true } })
    local ok, err = pcall(hl.dispatch, hl.dsp.focus({ window = selector }))
    hl.config({ cursor = { no_warps = prev } })
    if not ok then error(err, 0) end
end

function M.hyprland_backend()
    local function sel(a) return "address:" .. a end
    return {
        now = read_uptime_ms,
        get_window = function(a) return hl.get_window(sel(a)) end,
        active_window = function() return hl.get_active_window() end,
        focus = function(a) focus_without_warp(sel(a)) end,
        raise = function(a) hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = sel(a) })) end,
        after = function(ms, cb) return hl.timer(cb, { timeout = ms, type = "oneshot" }) end,
        on = function(event, cb) return hl.on(event, cb) end,
        log = print,
    }
end

-- Registers the urgent handler and the notify_focus global that `hyprctl eval` reaches
-- (eval runs in the config's Lua state). Every entry point is guarded so a fault here
-- can never break notification clicks or the config.
function M.setup(be)
    be = be or M.hyprland_backend()
    local nf = M.new(be)
    local function guard(fn, arg)
        local ok, err = pcall(fn, arg)
        if not ok then pcall(be.log, "notify-focus: " .. tostring(err)) end
    end
    be.on("window.urgent", function(w) guard(nf.urgent, w) end)
    _G.notify_focus = { clicked = function(app) guard(nf.clicked, app) end }
    return nf
end

return M
