--[[
carry.lua — window-carry animation for Hyprland (Lua config runtime, Lua 5.5).

What it does
  Super + Shift + period / comma switch to the next or previous workspace and take the
  focused floating window along. Hyprland can slide workspaces, but it has no per-window
  animation across that slide: the window would simply be teleported. This module makes
  the window look like it is thrown by the switch, leaning into the direction of travel
  and easing back to where it started.

How it does it
  The carried window is pinned. A pinned window renders at its own position, above the
  workspace layer, is untouched by the workspace slide, and is reassigned to whatever
  workspace is switched to. That is exactly the "carried" behaviour, so the slide and the
  carry can run at the same time without fighting each other.

  With the window pinned, its position is ours to animate. The `no_anim` window prop is
  set for the duration of the flight so Hyprland's own move animation does not smooth our
  writes: with no_anim each position write warps on the next tick, which is what a hand
  written animation needs. A repeating timer (2 ms, 4 ms for XWayland clients, which are
  costlier to move) integrates the physics and writes one absolute, whole-pixel position
  per tick.

  At the end of the flight the window is put back at its exact home position while
  no_anim is still set (so the correction is instant and invisible), then unpinned, moved
  home once more (unpinning re-runs the floating layout and can nudge it), and no_anim is
  cleared. Home never moves: the window ends the switch where it began, only on a
  different workspace.

Single-monitor assumption
  Pinning, unpinning and cross-workspace focus are all monitor-local in Hyprland. A
  workspace switch only carries pinned windows that live on the workspace being left on
  that monitor (Monitor.cpp, "move pinned windows"), and unpinning reassigns the window
  to the active workspace of the monitor it is on (ConfigActions.cpp, pinWindow). A carry
  whose destination workspace already exists on a different monitor would therefore leave
  the window behind, so press() checks that first and falls back to the stock move. The
  finish paths (settled, superseded, reload, watchdog) assume the window is still on the
  monitor it started on: they write the recorded home position back, which is only the
  right answer while the flight stayed on one monitor. A monitor change mid-flight is not
  something this module tries to recover from beyond putting the window down cleanly.

Physics
  Two cascaded damped springs, in screen pixels, integrated with the closed-form spring
  step used by hyprutils (exact for any dt, never unstable; there is no sub-millisecond
  wall clock in this runtime, so the step is a fixed dt derived from the timer period).
  A "handle" h chases a target offset T; the window offset o chases the handle. The
  cascade is what gives the soft start: the window cannot jerk, because the thing it
  follows starts at rest too. T is `side * A` for the first turn_ms of the switch and 0
  afterwards, so the window leans out and is then pulled home.

Tunables (M.config)
  throw          fraction of monitor width to lean, before edge clamping
  min_throw      floor for that lean when there is little room to the edge
  edge_margin    pixels of monitor edge kept free (a pinned window that stops
                 intersecting its monitor gets re-fitted by the layout, which would
                 teleport it)
  lead           multiplier on the offset actually written (1 = as computed)
  turn_ms        how long the lean is held before the spring is released back to home
  handle_omega   stiffness of the handle spring: higher starts the throw sharper
  window_omega   stiffness of the window spring following the handle
  window_zeta    damping ratio of that spring: 1 = no bounce, below 1 = soft bounce
  tick_ms        timer period; tick_ms_xwayland is used for XWayland windows
  tick_scale     time scaling for slow-motion inspection (1 = real time)
  settle_px/vel  how close to home and how slow the window must be to call it done
  slide_done     how far through the workspace slide the switch must be to call it done
  max_flight_ms  watchdog: a flight is force-ended after this long. Enforced twice, on
                 integrated tick time and on a coarse os.time() wall clock, because a
                 coalesced or throttled timer makes tick time run slower than real time
                 and a window must never stay pinned because ticks stopped arriving.
  clock          adapt the physics step to real time. The timer is nominally 2 ms but
                 under the full-screen redraw of a workspace slide it fires every 4 to
                 5 ms, so a fixed step ran the flight over twice as slow as designed.
                 /proc/uptime (10 ms resolution) is read every tick; the true period is
                 estimated as a running mean seeded by the previous flight, and a small
                 fraction of the accumulated drift is folded into each step so the
                 correction is smooth rather than a per-tick jitter.
  clock_gain     fraction of the drift corrected per tick (0.03 = over about 30 ticks)
  clock_prior_ticks  weight of the previous flight's period estimate, in ticks
  max_step_ms    largest single physics step, so a compositor stall cannot teleport
  land_stable_ticks  landing: consecutive ticks the window must read back at home
  land_max_ticks     landing: give up (and clear no_anim anyway) after this many ticks
  slide          the workspace slide spring being matched, for the chaining rule
  chain_rule     "middle" (see below) or a number 0..1 slide-progress threshold
  min_ws/max_ws  workspace range the keybinds may reach

Chaining rule
  A second press during a flight is either too early to mean anything or a genuine "keep
  going". The test is whether the workspace arriving on screen has already covered the
  middle of the carried window: the slide position is reconstructed from slide_progress,
  the arriving workspace edge is computed from it, and the press counts only once that
  edge has passed the window's midpoint. Before that the press is ignored outright, so
  a key repeat or a fumbled double tap cannot queue up a stack of switches. After it, the
  destination and the throw direction are updated in place and the physics state is kept,
  so the window bends into the new direction instead of restarting. The same test covers
  pressing the opposite direction to come back one workspace.
]]

local M = {}

M.config = {
  throw = 0.30, min_throw = 0.12, edge_margin = 8, lead = 1,
  turn_ms = 130,
  handle_omega = 18,
  window_omega = 14, window_zeta = 1.0,
  tick_ms = 2, tick_ms_xwayland = 4, tick_scale = 1.0,
  settle_px = 0.5, settle_vel = 8, slide_done = 0.995,
  max_flight_ms = 3000,
  clock = true, clock_gain = 0.03, clock_prior_ticks = 25, max_step_ms = 12,
  land_stable_ticks = 3, land_max_ticks = 40,
  slide = { mass = 1, stiffness = 110, damping = 20 },
  chain_rule = "middle",
  min_ws = 1, max_ws = 10,
}

local abs, exp, sqrt, sin, cos, floor = math.abs, math.exp, math.sqrt, math.sin, math.cos, math.floor

-- Closed-form step of a damped spring, same maths as hyprutils Spring.cpp. Returns the
-- new position and velocity after dt seconds. Exact for any dt, so a coarse or a jittery
-- tick cannot make it explode the way a Euler step would.
local function spring_step(x, v, goal, omega, zeta, dt)
  x, v, goal = x or 0, v or 0, goal or 0
  omega = omega or 1
  zeta = zeta or 1
  dt = dt or 0
  if dt <= 0 or omega <= 0 then return x, v end

  local d = x - goal            -- displacement from the goal
  local gamma = zeta * omega    -- decay rate
  local eps = math.max(omega, 1) * 0.0001

  if gamma < omega - eps then
    -- under-damped: decaying oscillation, overshoots the goal
    local wd = sqrt(omega * omega - gamma * gamma)
    local e, s, c = exp(-gamma * dt), sin(wd * dt), cos(wd * dt)
    local nd = e * (d * c + ((v + gamma * d) / wd) * s)
    local nv = e * (v * c - ((gamma * v + omega * omega * d) / wd) * s)
    return goal + nd, nv
  elseif gamma <= omega + eps then
    -- critically damped: fastest approach without overshoot
    local e = exp(-gamma * dt)
    local b = v + gamma * d
    return goal + e * (d + b * dt), e * (v - gamma * b * dt)
  end

  -- over-damped: two real roots, crawls in
  local root = sqrt(gamma * gamma - omega * omega)
  local r1, r2 = -gamma + root, -gamma - root
  local a = (v - r2 * d) / (r1 - r2)
  local b = d - a
  local e1, e2 = exp(r1 * dt), exp(r2 * dt)
  return goal + a * e1 + b * e2, a * r1 * e1 + b * r2 * e2
end

-- Position, normalised 0..1, of the workspace slide at time t after it started: a unit
-- spring released from rest towards 1. Hyprland animates the slide with this same closed
-- form, so this reproduces where the incoming workspace is on screen without asking the
-- compositor. Used by the chaining rule and by the settle test.
local function slide_progress(t, slide)
  slide = slide or M.config.slide
  t = t or 0
  if t <= 0 then return 0 end
  local mass = math.max(slide.mass or 1, 0.0001)
  local stiffness = math.max(slide.stiffness or 1, 0.0001)
  local damping = math.max(slide.damping or 0, 0)
  local omega0 = sqrt(stiffness / mass)
  local gamma = damping / (2 * mass)
  local x = spring_step(0, 0, 1, omega0, (omega0 > 0) and (gamma / omega0) or 1, t)
  return x
end

M.physics = { spring_step = spring_step, slide_progress = slide_progress }

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function round(v) return floor(v + 0.5) end

local function strip_addr(a)
  if type(a) ~= "string" then return nil end
  return (a:gsub("^address:", ""))
end

-- Vec2 in either shape: { x =, y = } or { [1], [2] }. Returns nil, nil when neither
-- shape yields numbers, so callers can tell "absent" from "zero".
local function vec(v)
  if v == nil then return nil, nil end
  if type(v) == "number" then return v, v end
  local x, y = v.x, v.y
  if type(x) ~= "number" or type(y) ~= "number" then x, y = v[1], v[2] end
  if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
  return x, y
end

local function raw_address(w) return w.address end

-- Address out of whatever an event handed us: a normalised table, an HL.Window, a string.
-- Returns nil when it cannot be read at all, which callers must treat as "unknown", not
-- as "not ours".
local function address_of(w)
  if type(w) == "string" then return strip_addr(w) end
  if w == nil then return nil end
  local ok, a = pcall(raw_address, w)
  if ok then return strip_addr(a) end
  return nil
end

-- Plain field reads, run once under a single pcall by norm_window below. HL.Window and
-- HL.Monitor are userdata with an __index that can raise, so the reads are protected as
-- one block rather than one closure per field.
local function read_window(u)
  local addr = strip_addr(u.address)
  if not addr then return nil end
  local x, y = vec(u.at)
  local w, h = vec(u.size)
  local ws = u.workspace
  local mu = u.monitor
  local mon
  if mu ~= nil then
    local scale = tonumber(mu.scale) or 0
    -- HL.Monitor.size is m_size, already logical (pixel size divided by scale);
    -- .width/.height are m_pixelSize, physical. Prefer size, fall back to the division.
    local mw, mh = vec(mu.size)
    if not (mw and mh and mw > 0 and mh > 0) then
      mw, mh = tonumber(mu.width), tonumber(mu.height)
      if mw and mh and scale > 0 then mw, mh = mw / scale, mh / scale else mw, mh = nil, nil end
    end
    mon = {
      id = tonumber(mu.id) or -1,
      x = tonumber(mu.x) or 0,
      y = tonumber(mu.y) or 0,
      width = mw, height = mh, scale = scale,
    }
  end
  return {
    address = addr, x = x or 0, y = y or 0, w = w or 0, h = h or 0,
    floating = u.floating and true or false,
    fullscreen = tonumber(u.fullscreen) or 0,
    pinned = u.pinned and true or false,
    xwayland = u.xwayland and true or false,
    workspace_id = tonumber(ws and ws.id) or -1,
    monitor = mon,
  }
end

local function norm_window(u)
  if u == nil then return nil end
  local ok, w = pcall(read_window, u)
  if ok then return w end
  return nil
end

local function read_workspace_monitor_id(ws)
  if ws == nil then return nil end
  local mon = ws.monitor
  if mon == nil then return nil end
  return tonumber(mon.id)
end

-- Default backend: the only place in the module that talks to the compositor. Built
-- lazily so the file loads and the physics can be tested with no `hl` global present.
-- Coarse wall clock: /proc/uptime, 10 ms resolution, about 20 us per read. The Lua
-- runtime has nothing finer (os.time is whole seconds, os.clock is CPU time).
local function read_uptime_ms()
  local f = io.open("/proc/uptime", "r")
  if not f then return nil end
  local line = f:read("l")
  f:close()
  local v = line and tonumber(line:match("^(%S+)"))
  return v and v * 1000 or nil
end

local function default_backend()
  local hl = rawget(_G, "hl")
  -- This API has no logging function. print() goes to the compositor's stdout, which
  -- is not captured anywhere on this machine, so a copy is appended to a small log in
  -- the runtime dir (tmpfs, gone at logout): $XDG_RUNTIME_DIR/carry.log.
  local log_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/carry.log"
  local function log(msg)
    msg = "[carry] " .. tostring(msg)
    pcall(print, msg)
    local f = io.open(log_path, "a")
    if f then f:write(os.date("%H:%M:%S "), msg, "\n"); f:close() end
  end
  if not hl then
    local noop = function() end
    return {
      active_window = function() return nil end,
      get_window = function() return nil end,
      workspace_monitor_id = function() return nil end,
      pin = noop, set_no_anim = noop, move_to = noop,
      focus_workspace = noop, move_window_to_workspace_follow = noop,
      timer = function() return { set_enabled = noop, is_enabled = function() return false end } end,
      on = noop, log = log,
    }
  end
  local function sel(addr) return "address:" .. tostring(addr) end
  return {
    active_window = function() return norm_window(hl.get_active_window()) end,
    get_window = function(addr) return norm_window(hl.get_window(sel(addr))) end,
    -- nil means "no such workspace yet", which is fine: it will be created on the
    -- current monitor. A number that is not the window's monitor means the carry
    -- cannot work and the caller should fall back to the stock move.
    workspace_monitor_id = function(id)
      local ok, mid = pcall(read_workspace_monitor_id, hl.get_workspace(id))
      if ok then return mid end
      return nil
    end,
    pin = function(addr, on)
      hl.dispatch(hl.dsp.window.pin({ action = on and "enable" or "disable", window = sel(addr) }))
    end,
    -- `window` is the selector option name for set_prop (hl.window.set_prop takes
    -- { prop, value, window? }); "unset" drops the set_prop override again.
    set_no_anim = function(addr, on)
      hl.dispatch(hl.dsp.window.set_prop({ prop = "no_anim", value = on and "1" or "unset", window = sel(addr) }))
    end,
    move_to = function(addr, x, y)
      hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = sel(addr) }))
    end,
    focus_workspace = function(id) hl.dispatch(hl.dsp.focus({ workspace = id })) end,
    move_window_to_workspace_follow = function(id)
      hl.dispatch(hl.dsp.window.move({ workspace = id, follow = true }))
    end,
    timer = function(cb, ms) return hl.timer(cb, { timeout = ms, type = "repeat" }) end,
    clock_ms = read_uptime_ms,
    on = function(event, cb) return hl.on(event, cb) end,
    log = log,
  }
end

-- Live state. One table, reused, so M.state() stays valid across flights.
-- phase   "idle", "flying" or "landing" (unpinned, correcting position, no_anim still set)
-- h, hv   handle position and velocity (what the window chases)
-- o, ov   window offset from home, and its velocity
-- w       carried window width; win_h its height
-- A       throw amplitude for the current side
local st = { phase = "idle" }

-- One timer and one set of event subscriptions per module instance, outliving any single
-- flight: creating a timer per flight leaks one per keypress, and re-running the config
-- would stack another set of handlers on every reload.
local timer, subs = nil, {}

-- Measured timer period per nominal period, carried from one flight to the next so the
-- clock estimate starts close instead of from the nominal value every time.
local learned_period = {}

local function reset_state()
  for k in pairs(st) do st[k] = nil end
  st.phase = "idle"
  st.h, st.hv, st.o, st.ov = 0, 0, 0, 0
end
reset_state()

function M.state() return st end

local function stop_timer()
  if not timer then return end
  pcall(timer.set_enabled, timer, false)
end

-- Give up on a flight without touching the compositor: for a window that no longer
-- exists, where every dispatch would be aimed at a dead address.
local function drop_state()
  reset_state()
  stop_timer()
end

-- Throw amplitude for `side`, clamped so the window can never stop intersecting its
-- monitor. Room is measured from where the window is now (a chained press starts from a
-- displaced window) and additionally capped so that home + lead * side * A is still on
-- the monitor, which is the position actually written.
local function throw_amp(side)
  local cfg, mon = M.config, st.mon
  if not mon then return 0 end
  local lead = math.max(abs(cfg.lead or 1), 1e-6)
  local cur_x = st.home_x + (cfg.lead or 1) * st.o
  local room_now, room_home
  if side == 1 then
    room_now = (mon.x + mon.width) - (cur_x + st.w) - cfg.edge_margin
    room_home = (mon.x + mon.width) - (st.home_x + st.w) - cfg.edge_margin
  else
    room_now = cur_x - mon.x - cfg.edge_margin
    room_home = st.home_x - mon.x - cfg.edge_margin
  end
  local avail = math.min(room_now, room_home) / lead
  local a = clamp(cfg.throw * mon.width, 0, math.max(avail, 0))
  local floor_a = math.max(math.min(cfg.min_throw * mon.width, avail), 0)
  return math.max(a, floor_a)
end

-- Has the arriving workspace covered the middle of the carried window yet?
local function crossed(p)
  local cfg = M.config
  if type(cfg.chain_rule) == "number" then return p >= cfg.chain_rule end
  local mon = st.mon
  if not mon then return true end
  local mid = st.home_x + cfg.lead * st.o + st.w / 2
  if st.side == 1 then
    -- arriving from the right: its left edge walks in from the right monitor edge
    return (mon.x + mon.width * (1 - p)) < mid
  end
  -- arriving from the left: its right edge walks in from the left monitor edge
  return (mon.x + mon.width * p) > mid
end

-- End a flight now: timer off, window home, unpinned, no_anim cleared. Idempotent (the
-- state is cleared first, so a re-entrant call sees idle) and never raises, including
-- when the window has already gone.
--
-- Each compositor step is its own pcall and runs whatever happened to the ones before
-- it. Hyprland refuses to unpin a window that has stopped being floating or has gone
-- fullscreen (pinWindow returns an error in that state), and a single guarded sequence
-- would then skip clearing no_anim and leave the window animation-less forever.
--
-- Unpinning re-runs the floating layout for the window (assignToSpace, then a work-area
-- fit), and that can move it by a pixel after this function's exact-home write. Writing
-- home blind a second time did not cure it: the window still ended one pixel off and
-- visibly hopped there once no_anim was cleared. So finish() only puts the window down
-- and unpins it; the timer then runs a short "landing" phase that reads the position
-- back and corrects whatever the layout did, with no_anim still set so each correction
-- is instant and invisible. no_anim is cleared only once the window reads back at home.
function M.finish(reason)
  if st.phase ~= "flying" then return end
  local be, addr = M.backend, st.addr
  local home_x, home_y = st.home_x, st.home_y
  if st.dt_nom and st.period_est and (st.ticks or 0) >= 20 then
    learned_period[st.dt_nom] = st.period_est
  end
  pcall(be and be.log or print, string.format("carry: flight ended (%s) after %d ticks, %.0f ms, timer period %.2f ms%s",
    tostring(reason), st.ticks or 0, (st.t or 0) * 1000, st.period_est or 0,
    st.real0 and "" or " (no clock, fixed step)"))
  reset_state()
  if not be then stop_timer(); return end

  local ok, w = pcall(be.get_window, addr)
  if ok and w == nil then
    stop_timer()
    if reason and reason ~= "settled" then pcall(be.log, "carry: flight ended, window gone (" .. tostring(reason) .. ")") end
    return
  end
  -- exact home while no_anim is still set, so this lands as one instant correction
  pcall(be.move_to, addr, home_x, home_y)
  pcall(be.pin, addr, false)

  st.phase = "landing"
  st.addr, st.home_x, st.home_y = addr, home_x, home_y
  st.land_ticks, st.land_stable = 0, 0
  st.land_bias_x, st.land_bias_y = 0, 0
  -- the timer is still armed from the flight; landing_body takes over on the next tick
end

-- Finish the landing synchronously: one read-back correction, then clear no_anim. Used
-- where the timer cannot be relied on to keep ticking (reload, teardown) or where the
-- next flight must start now (a new press).
function M.land(reason)
  if st.phase ~= "landing" then return end
  local be, addr = M.backend, st.addr
  local home_x, home_y = st.home_x, st.home_y
  local bias_x, bias_y = st.land_bias_x, st.land_bias_y
  reset_state()
  stop_timer()
  if not be then return end
  local ok, w = pcall(be.get_window, addr)
  if ok and w == nil then return end
  if ok and w and w.floating and (abs(w.x - home_x) >= 0.5 or abs(w.y - home_y) >= 0.5) then
    pcall(be.move_to, addr, home_x + bias_x, home_y + bias_y)
  end
  pcall(be.set_no_anim, addr, false)
  if reason and reason ~= "settled" then pcall(be.log, "carry: landed (" .. tostring(reason) .. ")") end
end

-- One landing tick. The position is read back every tick; a reading that differs from
-- home AND has held still since the previous tick means the compositor has applied our
-- last write and still disagrees, so the residual is folded into a bias and written
-- again. A reading that is still changing is left alone (the write is in transit). Once
-- the window reads back at home for land_stable_ticks in a row, no_anim is cleared.
local function landing_body()
  local cfg, be = M.config, M.backend
  st.land_ticks = st.land_ticks + 1
  local w = be.get_window(st.addr)
  if not w then return drop_state() end

  local dx, dy = w.x - st.home_x, w.y - st.home_y
  if not w.floating then
    st.land_stable = cfg.land_stable_ticks        -- tiled now: nothing to correct
  elseif abs(dx) < 0.5 and abs(dy) < 0.5 then
    st.land_stable = st.land_stable + 1
  elseif st.land_lx and abs(w.x - st.land_lx) < 0.5 and abs(w.y - st.land_ly) < 0.5 then
    st.land_bias_x, st.land_bias_y = st.land_bias_x - dx, st.land_bias_y - dy
    pcall(be.log, string.format("carry: landing correction %g,%g px (tick %d)", -dx, -dy, st.land_ticks))
    be.move_to(st.addr, st.home_x + st.land_bias_x, st.home_y + st.land_bias_y)
    st.land_stable = 0
  end
  st.land_lx, st.land_ly = w.x, w.y

  if st.land_stable >= cfg.land_stable_ticks then
    be.set_no_anim(st.addr, false)
    reset_state()
    stop_timer()
  elseif st.land_ticks >= cfg.land_max_ticks then
    pcall(be.log, string.format("carry: landing gave up %g,%g px off home", dx, dy))
    be.set_no_anim(st.addr, false)
    reset_state()
    stop_timer()
  end
end

-- Whole-pixel position writes. The compositor lays windows out on the pixel grid, so
-- sub-pixel writes buy nothing, but naive rounding at a 2 ms tick injects a one pixel
-- beat (500 px/s of apparent velocity noise) that swamps the real per-tick velocity
-- change of about 130 px/s. The written step is therefore slew limited to one pixel of
-- change per tick: the physics never asks for more than about 0.35 px of step change per
-- tick, so the limiter only ever trims quantisation beats, and any pixel it holds back
-- is given back on the next tick. Deviation from the exact trajectory stays under a
-- pixel, and finish() writes the exact home position regardless.
local function quantise(exact)
  local want = round(exact)
  if st.last_px then
    local step = want - st.last_px
    local prev = st.last_step or step
    if step > prev + 1 then step = prev + 1 elseif step < prev - 1 then step = prev - 1 end
    want = st.last_px + step
    st.last_step = step
  else
    st.last_step = 0
  end
  st.last_px = want
  return want
end

-- Advance integrated time by one step. With a clock, the step is the estimated real
-- timer period plus a small share of the drift between real elapsed time and integrated
-- time, so the flight tracks the workspace slide in real time however slowly the ticks
-- arrive; without one (no /proc, or the test harness) it is the fixed nominal step.
local function advance_time()
  local cfg = M.config
  local dt_ms = st.dt_nom
  st.ticks = st.ticks + 1
  if st.real0 then
    local now = M.backend.clock_ms()
    if now then
      local real = now - st.real0
      local n = cfg.clock_prior_ticks
      st.period_est = (n * st.period_prior + real) / (n + st.ticks)
      local drift = real - (st.sim_ms + st.period_est)
      dt_ms = st.period_est + drift * cfg.clock_gain
      if dt_ms < 0.5 * st.dt_nom then dt_ms = 0.5 * st.dt_nom end
      if dt_ms > cfg.max_step_ms then dt_ms = cfg.max_step_ms end
    end
  end
  st.sim_ms = st.sim_ms + dt_ms
  st.dt = dt_ms / 1000 * cfg.tick_scale
  st.t = st.t + st.dt
end

local function tick_body()
  local cfg, be = M.config, M.backend
  advance_time()

  local w = be.get_window(st.addr)
  if not w or not w.floating or w.fullscreen ~= 0 or not w.pinned then
    return M.finish("window changed")
  end

  local since = st.t - st.t_press
  local turn = cfg.turn_ms / 1000
  local target = (since < turn) and (st.side * st.A) or 0

  st.h, st.hv = spring_step(st.h, st.hv, target, cfg.handle_omega, 1.0, st.dt)
  st.o, st.ov = spring_step(st.o, st.ov, st.h, cfg.window_omega, cfg.window_zeta, st.dt)
  be.move_to(st.addr, quantise(st.home_x + cfg.lead * st.o), round(st.home_y))

  if since > turn and abs(st.o) < cfg.settle_px and abs(st.ov) < cfg.settle_vel
     and slide_progress(since, cfg.slide) >= cfg.slide_done then
    return M.finish("settled")
  end
  if (st.t - st.t_start) * 1000 > cfg.max_flight_ms then
    return M.finish("watchdog")
  end
  -- Wall-clock backstop: os.time() has 1 s resolution, so allow one extra second over
  -- the configured budget. This only ever fires when ticks are arriving slower than
  -- real time, which the integrated clock above cannot see.
  if st.t_wall and (os.time() - st.t_wall) >= math.ceil(cfg.max_flight_ms / 1000) + 1 then
    return M.finish("watchdog (wall clock)")
  end
end

-- An error thrown inside an hl.timer callback is swallowed and leaves the timer running,
-- so the tick body is always guarded: one log line, then the flight is ended cleanly.
local function tick()
  if st.phase == "landing" then
    local ok, err = pcall(landing_body)
    if not ok then
      pcall(M.backend.log, "carry: landing error: " .. tostring(err))
      M.land("error: " .. tostring(err))
    end
    return
  end
  if st.phase ~= "flying" then stop_timer(); return end
  local ok, err = pcall(tick_body)
  if not ok then
    pcall(M.backend.log, "carry: tick error: " .. tostring(err))
    M.finish("error: " .. tostring(err))
  end
end

-- Start, or re-arm, the single per-instance timer at the requested period.
local function arm_timer(ms)
  if timer then
    if type(timer.set_timeout) == "function" then pcall(timer.set_timeout, timer, ms) end
    pcall(timer.set_enabled, timer, true)
    return
  end
  timer = M.backend.timer(tick, ms)   -- starts enabled
end

local function begin_flight(w, target, dir)
  local cfg, be = M.config, M.backend
  local ms = w.xwayland and cfg.tick_ms_xwayland or cfg.tick_ms
  reset_state()
  st.phase = "flying"
  st.addr = w.address
  st.home_x, st.home_y, st.w, st.win_h = w.x, w.y, w.w, w.h
  st.mon = w.monitor
  st.dest, st.side = target, dir
  st.t, st.t_press, st.t_start = 0, 0, 0
  st.t_wall = os.time()
  st.xwayland = w.xwayland
  st.A = throw_amp(dir)
  st.dt_nom, st.dt = ms, ms / 1000 * cfg.tick_scale
  st.ticks, st.sim_ms = 0, 0
  st.period_prior = learned_period[ms] or ms
  st.period_est = st.period_prior
  if cfg.clock and type(be.clock_ms) == "function" then
    local ok, now = pcall(be.clock_ms)
    if ok and type(now) == "number" then st.real0 = now end
  end

  pcall(be.log, string.format(
    "carry: %s -> ws %d, monitor %s logical %gx%g at %g,%g scale %g, throw %g px",
    st.addr, target, tostring(st.mon.id), st.mon.width, st.mon.height, st.mon.x, st.mon.y,
    st.mon.scale or 1, st.A))

  be.pin(st.addr, true)
  be.set_no_anim(st.addr, true)
  be.focus_workspace(target)
  arm_timer(ms)
end

-- Is the monitor geometry usable? Without a trustworthy logical width there is no throw
-- distance and no edge clamp, and an unclamped throw can push a pinned window off its
-- monitor, where the layout re-fits it with a teleport.
local function monitor_ok(mon)
  if not mon then return false end
  local w, h, s = tonumber(mon.width), tonumber(mon.height), tonumber(mon.scale)
  return (w ~= nil and w > 0) and (h ~= nil and h > 0) and (s ~= nil and s > 0)
end

-- Would the destination workspace put the window on another monitor? Only a workspace
-- that already exists can, and only then does the carry have to be refused.
local function other_monitor(target, mon)
  local be = M.backend
  if type(be.workspace_monitor_id) ~= "function" then return false end
  local ok, mid = pcall(be.workspace_monitor_id, target)
  if not ok or mid == nil then return false end
  local own = mon and tonumber(mon.id)
  if own == nil then return false end
  return mid ~= own
end

-- Keybind entry point. dir is 1 (next workspace) or -1 (previous).
-- Shared entry for both key styles. `dir` is +1/-1 for the next/previous keys; `target`
-- is an absolute workspace for the Super + Shift + number keys, in which case the
-- direction is derived from where the target sits relative to the workspace being
-- left. A jump of several workspaces is one slide in Hyprland, so it is one flight here.
local function go(dir, target)
  if not M.backend then M.setup() end
  local cfg, be = M.config, M.backend

  if st.phase == "landing" then M.land("new press") end

  if st.phase == "flying" then
    local active = be.active_window()
    if not active or active.address ~= st.addr then
      -- focus moved elsewhere mid-flight: put the carried window down, then start fresh
      M.finish("superseded")
      M.land("superseded")
      return go(dir, target)
    end
    local p = slide_progress(st.t - st.t_press, cfg.slide)
    if not crossed(p) then return end       -- too early to mean anything: ignore
    target = target or st.dest + dir
    if target == st.dest or target < cfg.min_ws or target > cfg.max_ws then return end
    dir = target > st.dest and 1 or -1
    -- Keep h, hv, o, ov: the window bends into the new direction instead of restarting.
    st.dest, st.side = target, dir
    st.t_press = st.t
    st.A = throw_amp(dir)
    be.focus_workspace(target)
    return
  end

  local w = be.active_window()
  if not w then return end
  target = target or w.workspace_id + dir
  if target == w.workspace_id or target < cfg.min_ws or target > cfg.max_ws then return end
  dir = target > w.workspace_id and 1 or -1

  local eligible = w.floating and w.fullscreen == 0 and not w.pinned and w.workspace_id > 0
                   and monitor_ok(w.monitor) and not other_monitor(target, w.monitor)
  if not eligible then
    be.move_window_to_workspace_follow(target)  -- stock behaviour, no animation
    return
  end
  begin_flight(w, target, dir)
end

-- Super + Shift + period / comma: next or previous workspace.
function M.press(dir)
  if dir ~= 1 and dir ~= -1 then return end
  return go(dir, nil)
end

-- Super + Shift + [0-9]: a specific workspace.
function M.press_to(ws)
  ws = tonumber(ws)
  if not ws or ws ~= floor(ws) then return end
  return go(nil, ws)
end

-- Unsubscribe and stop the timer. Called on reload by the incoming instance, so handlers
-- and timers do not accumulate one set per `hyprctl reload`.
function M.teardown()
  M.land("teardown")
  local old = subs
  subs = {}
  for i = 1, #old do
    local s = old[i]
    if s ~= nil and type(s) ~= "boolean" then pcall(function() s:remove() end) end
  end
  stop_timer()
  timer = nil
end

function M.setup(backend)
  M.backend = backend or default_backend()
  local be = M.backend

  -- The carried window vanished: drop everything without dispatching at a dead address.
  -- An unreadable payload must never be treated as "not ours" and must never end the
  -- flight blindly either, or a foreign window closing would leave ours pinned with
  -- no_anim set for good.
  subs[#subs + 1] = be.on("window.close", function(w)
    if st.phase == "idle" then return end
    local a = address_of(w)
    if a ~= nil then
      if a == st.addr then drop_state() end
      return
    end
    local ok, still = pcall(be.get_window, st.addr)
    if ok and still == nil then drop_state() end
    -- otherwise ours is alive, or unknowable: let the flight (and its watchdogs) run
  end)

  subs[#subs + 1] = be.on("config.reloaded", function() M.finish("reload"); M.land("reload") end)

  _G.__carry = M
  return M
end

-- Reload handshake: a previous instance of this module may be mid-flight with a pinned,
-- no_anim window, a live timer and live event handlers. Ask it to put the window down
-- and let go of both before it is replaced. __carry is claimed here as well as in
-- setup(), so a chunk that fails before setup() still hands over cleanly next time.
do
  local prev = rawget(_G, "__carry")
  if prev and prev ~= M then
    if type(prev.finish) == "function" then pcall(prev.finish, "module reloaded") end
    if type(prev.teardown) == "function" then pcall(prev.teardown) end
  end
  _G.__carry = M
end

return M
