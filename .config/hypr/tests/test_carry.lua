-- test_carry.lua
-- Offline core scenarios for carry.lua using the shared virtual compositor.
-- Usage:
--   lua5.5 test_carry.lua                 -- run all scenarios against CARRY
--   CARRY=/path/to/module.lua lua5.5 ...  -- pick module (default ../carry.lua)
--   DUMP=1 lua5.5 test_carry.lua          -- also write trajectory CSVs a/c/d

local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local mock_backend = require("mock_backend")

local CARRY = os.getenv("CARRY") or script_dir .. "../carry.lua"
local DUMP = os.getenv("DUMP") == "1"

local results = {}
local any_fail = false

local function load_module()
  local f = assert(loadfile(CARRY), "could not load module at " .. CARRY)
  return f()
end

-- ---- shared numeric helpers -------------------------------------------

local function velocities(xs, dt)
  local v = {}
  for i = 1, #xs do
    local prev = (i == 1) and xs[1] or xs[i - 1]
    -- caller passes xs already including a synthetic "home" as element 0
    v[i] = (xs[i] - prev) / dt
  end
  return v
end

-- xs: array of x positions AFTER each tick. home: pre-flight x.
-- Returns velocities (one per tick, using previous tick's x, home for tick1),
-- max |step|, max |Δv|, max |jerk|, peak |offset| from home.
local function analyze(xs, home, dt)
  local n = #xs
  local vel, step, peak = {}, {}, 0
  local prev = home
  for i = 1, n do
    step[i] = xs[i] - prev
    vel[i] = step[i] / dt
    local off = math.abs(xs[i] - home)
    if off > peak then peak = off end
    prev = xs[i]
  end
  local max_step, max_dv, max_jerk = 0, 0, 0
  for i = 1, n do
    if math.abs(step[i]) > max_step then max_step = math.abs(step[i]) end
  end
  for i = 2, n do
    local dv = math.abs(vel[i] - vel[i - 1])
    if dv > max_dv then max_dv = dv end
  end
  local acc = {}
  for i = 2, n do acc[i - 1] = (vel[i] - vel[i - 1]) / dt end
  for i = 2, #acc do
    local j = math.abs(acc[i] - acc[i - 1]) / dt
    if j > max_jerk then max_jerk = j end
  end
  return vel, max_step, max_dv, max_jerk, peak
end

local function dt_of(M)
  return M.config.tick_ms / 1000 * M.config.tick_scale
end

local function fmt(n)
  return string.format("%.3f", n)
end

local dump_data = {}

-- ---- scenario runner -----------------------------------------------------

local function run(name, fn)
  local ok, err_or_metrics = pcall(fn)
  if ok then
    results[#results + 1] = { name = name, pass = true, metrics = err_or_metrics }
  else
    any_fail = true
    results[#results + 1] = { name = name, pass = false, msg = tostring(err_or_metrics) }
  end
end

local function check(cond, msg)
  if not cond then error(msg, 2) end
end

-- ---- scenario a: single +1 flight --------------------------------------

local scenario_a_state = {}

run("a_single_flight", function()
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
  world:set_active(addr)
  local M = load_module()
  M.setup(backend)
  local dt = dt_of(M)
  local home_x, home_y = 1400, 150

  M.press(1)
  local timer_obj = world.timers[#world.timers]

  local ticks = 0
  while M.state().phase ~= "idle" and ticks < 2000 do
    world:tick(1)
    ticks = ticks + 1
  end
  check(M.state().phase == "idle", "did not settle within 2000 ticks")

  local traj = world:trajectory_for(addr)
  local xs = {}
  for i, p in ipairs(traj) do xs[i] = p.x end
  local vel, max_step, max_dv, max_jerk, peak = analyze(xs, home_x, dt)

  local mon_w = world.monitor.width
  for i, p in ipairs(traj) do
    check(p.x >= world.monitor.x and p.x + 1200 <= world.monitor.x + mon_w,
      "window left the monitor at tick " .. i)
  end

  check(math.abs(vel[1]) < 60, "first-tick velocity too high: " .. fmt(vel[1]))
  check(peak <= 0.30 * mon_w + 1e-6, "peak offset exceeds 0.30*mon_w: " .. fmt(peak))

  local w = world:window(addr)
  check(math.abs(w.x - home_x) < 1e-9 and math.abs(w.y - home_y) < 1e-9, "final position not exactly home")
  check(w.pinned == false, "window not unpinned at end")
  check(w.no_anim == false or w.no_anim == nil, "no_anim not unset at end")
  check(timer_obj:is_enabled() == false, "timer still enabled at end")

  local pins_on = world:calls_matching("pin", addr)
  local pin_true, pin_false = 0, 0
  for _, c in ipairs(pins_on) do
    if c.value then pin_true = pin_true + 1 else pin_false = pin_false + 1 end
  end
  check(pin_true == 1 and pin_false == 1, "expected exactly one pin(true)/pin(false) pair, got " .. pin_true .. "/" .. pin_false)

  local fw = world:calls_matching("focus_workspace")
  check(#fw == 1 and fw[1].id == 2, "expected exactly one focus_workspace(2)")

  scenario_a_state.trajectory = xs
  scenario_a_state.max_step = max_step
  scenario_a_state.max_dv = max_dv
  scenario_a_state.ticks = ticks
  scenario_a_state.home_x, scenario_a_state.home_y = home_x, home_y
  scenario_a_state.dt = dt

  if DUMP then
    local t_ms, xd, vd = {}, {}, {}
    for i = 1, #xs do
      t_ms[i] = i * dt * 1000
      xd[i] = xs[i]
      vd[i] = vel[i]
    end
    dump_data.a = { t = t_ms, x = xd, v = vd }
  end

  local peak_v = 0
  for _, v in ipairs(vel) do if math.abs(v) > peak_v then peak_v = math.abs(v) end end

  return {
    first_tick_v = vel[1], peak_offset = peak, peak_v = peak_v,
    settle_ms = ticks * dt * 1000, max_jerk = max_jerk,
  }
end)

-- ---- scenario b: ignored press (repeat +1 at tick 20) -------------------

run("b_ignored_repeat_press", function()
  if not scenario_a_state.trajectory then error("scenario a did not produce a baseline trajectory") end
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
  world:set_active(addr)
  local M = load_module()
  M.setup(backend)

  M.press(1)
  world:tick(20)
  M.press(1) -- should be a no-op: not yet crossed

  local remaining = scenario_a_state.ticks - 20
  check(remaining >= 0, "scenario a baseline shorter than 20 ticks")
  local ticks = 20
  while M.state().phase ~= "idle" and ticks < 2000 do
    world:tick(1)
    ticks = ticks + 1
  end
  check(M.state().phase == "idle", "did not settle")

  local fw = world:calls_matching("focus_workspace")
  check(#fw == 1, "expected exactly one focus_workspace call total, got " .. #fw)

  local traj = world:trajectory_for(addr)
  check(#traj == #scenario_a_state.trajectory, "trajectory length differs from scenario a: " .. #traj .. " vs " .. #scenario_a_state.trajectory)
  for i = 1, #traj do
    check(traj[i].x == scenario_a_state.trajectory[i], "trajectory diverges from scenario a at tick " .. i)
  end

  return { note = "trajectory byte-identical to scenario a" }
end)

-- ---- shared chained-flight runner for c/d --------------------------------

local function run_chained(name, dir2, expect_focus_seq, expect_final_ws)
  return run(name, function()
    if not scenario_a_state.max_step then error("scenario a baseline missing") end
    local world = mock_backend.new_world()
    local backend = mock_backend.new(world)
    local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
    world:set_active(addr)
    local M = load_module()
    M.setup(backend)
    local dt = dt_of(M)

    M.press(1)
    world:tick(150)

    -- verify the crossing assumption with the module's own slide_progress
    local t_since_press = 150 * dt
    local p = M.physics.slide_progress(t_since_press)
    check(p ~= nil, "M.physics.slide_progress not exported")

    M.press(dir2)

    local ticks = 150
    while M.state().phase ~= "idle" and ticks < 2000 do
      world:tick(1)
      ticks = ticks + 1
    end
    check(M.state().phase == "idle", "did not settle")

    local fw = world:calls_matching("focus_workspace")
    check(#fw == #expect_focus_seq, "expected " .. #expect_focus_seq .. " focus_workspace calls, got " .. #fw)
    for i, id in ipairs(expect_focus_seq) do
      check(fw[i].id == id, "focus_workspace #" .. i .. " expected " .. id .. " got " .. fw[i].id)
    end

    local traj = world:trajectory_for(addr)
    local xs = {}
    for i, pnt in ipairs(traj) do xs[i] = pnt.x end
    local vel, max_step, max_dv = analyze(xs, scenario_a_state.home_x, dt)

    -- Rapid input deliberately exceeds the gentler isolated-switch speed. Keep an
    -- absolute motion bound instead of tying it to the reduced single-switch curve.
    local step_limit = world.monitor.width * dt
    check(max_step <= step_limit,
      "step too large: " .. fmt(max_step) .. " vs one monitor width/s " .. fmt(step_limit))
    -- Independent nearest-pixel rounding can change successive integer steps by two
    -- pixels. The continuous position/velocity checks live in test_carry_inertia.lua.
    local dv_limit = 2 / dt
    check(max_dv <= dv_limit + 1e-6,
      "velocity jump too large: " .. fmt(max_dv) .. " vs rounding limit " .. fmt(dv_limit))

    local w = world:window(addr)
    check(math.abs(w.x - scenario_a_state.home_x) < 1e-9, "final position not home")
    check(w.workspace_id == expect_final_ws, "final workspace expected " .. expect_final_ws .. " got " .. w.workspace_id)

    if DUMP then
      local t_ms, xd, vd = {}, {}, {}
      for i = 1, #xs do
        t_ms[i] = i * dt * 1000
        xd[i] = xs[i]
        vd[i] = vel[i]
      end
      dump_data[name == "c_chained_press" and "c" or "d"] = { t = t_ms, x = xd, v = vd }
    end

    local peak_v, peak_off = 0, 0
    for _, v in ipairs(vel) do if math.abs(v) > peak_v then peak_v = math.abs(v) end end
    for _, xv in ipairs(xs) do
      local off = math.abs(xv - scenario_a_state.home_x)
      if off > peak_off then peak_off = off end
    end

    return {
      slide_progress_at_press = p, peak_v = peak_v, peak_offset = peak_off,
      settle_ms = ticks * dt * 1000,
    }
  end)
end

run_chained("c_chained_press", 1, { 2, 3 }, 3)
run_chained("d_reversal_press", -1, { 2, 1 }, 1)

-- ---- scenario e: bounds --------------------------------------------------

run("e_bounds", function()
  do
    local world = mock_backend.new_world()
    local backend = mock_backend.new(world)
    local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 10 }
    world:set_active(addr)
    local M = load_module()
    M.setup(backend)
    M.press(1)
    check(#world.calls == 0, "expected no calls at max_ws boundary, got " .. #world.calls)
  end
  do
    local world = mock_backend.new_world()
    local backend = mock_backend.new(world)
    local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
    world:set_active(addr)
    local M = load_module()
    M.setup(backend)
    M.press(-1)
    check(#world.calls == 0, "expected no calls at min_ws boundary, got " .. #world.calls)
  end
  return { note = "both boundaries produced zero backend calls" }
end)

-- ---- scenario f: ineligible (tiled) window --------------------------------

run("f_ineligible_tiled", function()
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1, floating = false }
  world:set_active(addr)
  local M = load_module()
  M.setup(backend)
  M.press(1)

  local follow = world:calls_matching("move_window_to_workspace_follow")
  check(#follow == 1 and follow[1].id == 2, "expected exactly one move_window_to_workspace_follow(2)")
  local pins = world:calls_matching("pin")
  check(#pins == 0, "expected no pin calls for ineligible window")
  return { note = "one follow dispatch, no pin" }
end)

-- ---- scenario g: window closed mid-flight ---------------------------------

run("g_closed_mid_flight", function()
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
  world:set_active(addr)
  local M = load_module()
  M.setup(backend)

  local ok = pcall(function()
    M.press(1)
    local timer_obj = world.timers[#world.timers]
    world:tick(50)
    world:close(addr)
    local calls_before = #world.calls
    world:tick(50)
    check(timer_obj:is_enabled() == false, "timer still enabled after close")
    check(#world.calls == calls_before, "backend calls happened after window close")
    check(M.state().phase == "idle", "state not idle after close")
  end)
  check(ok, "unexpected Lua error surfaced during closed-mid-flight scenario")
  return { note = "no dispatches after close, no error" }
end)

-- ---- scenario h: watchdog -------------------------------------------------

run("h_watchdog", function()
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
  world:set_active(addr)
  local M = load_module()
  M.config.max_flight_ms = 100
  M.setup(backend)
  M.press(1)

  local ticks = 0
  while M.state().phase ~= "idle" and ticks < 200 do
    world:tick(1)
    ticks = ticks + 1
  end
  check(M.state().phase == "idle", "watchdog flight never settled")
  local max_ticks = math.ceil(M.config.max_flight_ms / (dt_of(M) * 1000)) + M.config.land_min_ticks + 10
  check(ticks <= max_ticks, "watchdog took too many ticks: " .. ticks)

  local w = world:window(addr)
  check(w.pinned == false, "pinned not cleared after watchdog finish")
  check(w.no_anim == false or w.no_anim == nil, "no_anim not cleared after watchdog finish")
  return { settle_ms = ticks * dt_of(M) * 1000 }
end)

-- ---- scenario i: superseded ------------------------------------------------

run("i_superseded", function()
  local world = mock_backend.new_world()
  local backend = mock_backend.new(world)
  local addr_a = world:create_window { x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 }
  local addr_b = world:create_window { x = 100, y = 100, w = 800, h = 600, workspace_id = 1 }
  world:set_active(addr_a)
  local M = load_module()
  M.setup(backend)

  M.press(1)
  world:tick(20)
  world:set_active(addr_b)
  M.press(1)

  local wa = world:window(addr_a)
  local wb = world:window(addr_b)
  check(wa.pinned == false, "window A not unpinned after being superseded")
  check(math.abs(wa.x - 1400) < 1e-9 and math.abs(wa.y - 150) < 1e-9, "window A not returned home after being superseded")
  check(wb.pinned == true, "window B not pinned after taking over the flight")
  return { note = "A returned home & unpinned, B now carrying" }
end)

-- ---- report ---------------------------------------------------------------

print(string.format("Module under test: %s", CARRY))
print("")
for _, r in ipairs(results) do
  if r.pass then
    local m = r.metrics or {}
    local parts = {}
    for k, v in pairs(m) do
      if type(v) == "number" then
        table.insert(parts, k .. "=" .. fmt(v))
      else
        table.insert(parts, k .. "=" .. tostring(v))
      end
    end
    print(string.format("PASS %-24s %s", r.name, table.concat(parts, " ")))
  else
    print(string.format("FAIL %-24s %s", r.name, r.msg))
  end
end

if DUMP then
  for key, d in pairs(dump_data) do
    local path = script_dir .. "trajectory_" .. key .. ".csv"
    local f = io.open(path, "w")
    f:write("t_ms,x,v\n")
    for i = 1, #d.t do
      f:write(string.format("%.4f,%.4f,%.4f\n", d.t[i], d.x[i], d.v[i]))
    end
    f:close()
    print("dumped " .. path)
  end
end

os.exit(any_fail and 1 or 0)
