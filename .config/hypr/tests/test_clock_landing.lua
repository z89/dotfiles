-- Extra scenarios for the adaptive clock and the landing phase.
-- j: timer fires every 4.7 ms real time (nominal 2), clock quantised to 10 ms, unpin
--    nudges the window +1 px (as the floating layout re-fit does); the move dispatcher
--    applies writes one tick late (goal vs value). Expect: settle in real time close to
--    the fixed-step design figure, exact home, no_anim cleared only once home, smooth steps.
local script_dir = arg[0]:match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path
local mock_backend = require("mock_backend")
local CARRY = os.getenv("CARRY") or script_dir .. "../carry.lua"
local fails = 0
local function check(c, msg) if not c then fails = fails + 1; print("  FAIL " .. msg) end end

-- Measure this tuning's nominal trajectory, so clock accuracy is independent of the
-- chosen throw/settle duration. Motion intensity has its own regression suite.
local design_ms
do
  local world = mock_backend.new_world()
  local M = assert(loadfile(CARRY))()
  M.config.clock = false
  M.setup(mock_backend.new(world))
  local addr = world:create_window({ x = 1328, y = 152, w = 2055, h = 1133, workspace_id = 2 })
  world:set_active(addr)
  M.press(1)
  local ticks = 0
  while M.state().phase == "flying" and ticks < 3000 do world:tick(1); ticks = ticks + 1 end
  assert(M.state().phase == "landing", "nominal flight did not settle")
  design_ms = ticks * M.config.tick_ms
  M.land("test calibration")
end

local function scenario(period_ms, quant_ms, nudge, late)
  local world = mock_backend.new_world()
  local be = mock_backend.new(world)
  local real = 0
  be.clock_ms = function() return math.floor(real / quant_ms) * quant_ms end
  -- unpin nudges like the layout re-fit
  local raw_pin = be.pin
  be.pin = function(addr, b)
    raw_pin(addr, b)
    if b == false and nudge ~= 0 then local w = world.windows[addr]; if w then w.x = w.x + nudge end end
  end
  -- optional one-tick latency on position writes
  local pending
  local raw_move = be.move_to
  if late then
    be.move_to = function(addr, x, y)
      table.insert(world.calls, { op = "move_to", address = addr, x = x, y = y })
      pending = { addr = addr, x = x, y = y }
    end
  end
  local M = assert(loadfile(CARRY))()
  M.setup(be)
  local addr = world:create_window({ x = 1328, y = 152, w = 2055, h = 1133, workspace_id = 2 })
  world:set_active(addr)
  M.press(1)
  local dts, ticks, settled_at = {}, 0, nil
  local home_ok_before_unset = true
  while M.state().phase ~= "idle" and ticks < 3000 do
    if pending then local w = world.windows[pending.addr]; if w then w.x, w.y = pending.x, pending.y end; pending = nil end
    real = real + period_ms
    local before = #world.calls
    world:tick(1)
    ticks = ticks + 1
    if M.state().phase == "flying" then dts[#dts + 1] = M.state().dt * 1000 end
    if M.state().phase ~= "flying" and not settled_at then settled_at = real end
    for i = before + 1, #world.calls do
      local c = world.calls[i]
      if c.op == "set_no_anim" and c.value == false then
        local w = world.windows[addr]
        if w.x ~= 1328 or w.y ~= 152 then home_ok_before_unset = false end
      end
    end
  end
  local w = world.windows[addr]
  local maxjump = 0
  for i = 2, #dts do maxjump = math.max(maxjump, math.abs(dts[i] - dts[i - 1])) end
  print(string.format("  period=%.1f quant=%d nudge=%d late=%s: flight %.0f ms real, landing %.0f ms, final x=%g pinned=%s no_anim=%s, dt first=%.2f last=%.2f max_dt_jump=%.3f",
    period_ms, quant_ms, nudge, tostring(late), settled_at or -1, (real - (settled_at or real)), w.x, tostring(w.pinned), tostring(w.no_anim),
    dts[1] or -1, dts[#dts] or -1, maxjump))
  check(M.state().phase == "idle", "did not reach idle")
  check(w.x == 1328 and w.y == 152, "not at home at end")
  check(w.pinned == false and w.no_anim == false, "pin/no_anim not cleared")
  check(home_ok_before_unset, "no_anim cleared while window was off home")
  check(settled_at and math.abs(settled_at - design_ms) < 80,
    string.format("flight real time off nominal trajectory (%.0f ms)", design_ms))
  check(maxjump < 0.6, "physics step changed too abruptly between ticks")
  return M
end

print("j_slow_timer_quantised_clock_nudge")
scenario(4.7, 10, 1, false)
print("k_same_with_late_position_writes")
scenario(4.7, 10, 1, true)
print("l_fast_timer_no_nudge")
scenario(2.08, 10, 0, false)
print("m_second_flight_uses_learned_period")
do
  -- learned period is module-level: two flights on one module instance
  local world = mock_backend.new_world(); local be = mock_backend.new(world)
  local real = 0; be.clock_ms = function() return math.floor(real / 10) * 10 end
  local M = assert(loadfile(CARRY))(); M.setup(be)
  local addr = world:create_window({ x = 1328, y = 152, w = 2055, h = 1133, workspace_id = 2 }); world:set_active(addr)
  local function fly()
    M.press(1); local first
    while M.state().phase ~= "idle" do real = real + 4.7; world:tick(1); first = first or (M.state().dt and M.state().dt * 1000) end
    return first
  end
  local f1 = fly(); world.windows[addr].workspace_id = 3; local f2 = fly()
  print(string.format("  first step: flight 1 %.2f ms, flight 2 %.2f ms", f1, f2))
  check(f2 > 4.0 and f2 < 5.4, "second flight did not start from the learned period")
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
