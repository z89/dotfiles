-- Offline motion regression suite: lua5.5 ~/.config/hypr/tests/test_carry_inertia.lua
-- CARRY optionally selects an unwatched candidate module. No compositor calls.
local here = arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local mock = require("mock_backend")
local carry_path = os.getenv("CARRY") or here .. "../carry.lua"
local failures = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then failures = failures + 1 end
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
end

local function simulate(opts)
  opts = opts or {}
  local world = mock.new_world()
  world.monitor.width = opts.monitor_width or 5120
  world.monitor.x = opts.monitor_x or 0
  local backend = mock.new(world)
  local real = 0
  if opts.clock then backend.clock_ms = function() return math.floor(real / 10) * 10 end end
  local module = assert(loadfile(carry_path))()
  if opts.config then opts.config(module.config) end
  module.setup(backend)
  local x = opts.x or (world.monitor.x + 1400)
  local width = opts.width or 1200
  local direction = opts.direction or 1
  local addr = world:create_window({ x = x, y = 150, w = width, h = 800,
    workspace_id = direction == 1 and 1 or 10, xwayland = opts.xwayland })
  world:set_active(addr)
  if opts.target then module.press_to(opts.target) else module.press(direction) end
  local result = { peak = 0, rebound = 0, vmax = 0, chain_vmax = 0, error = 0, outside = 0,
                   intensity = 0, accepted = 1, samples = {} }
  local presses, last_accepted = opts.presses or {}, 0
  local next_press = 1
  local previous_x = x

  for tick = 1, 6000 do
    local period = type(opts.period) == "table" and opts.period[(tick - 1) % #opts.period + 1] or (opts.period or 2)
    real = real + period
    world:tick(1)
    local state = module.state()
    local window = world.windows[addr]
    if window.x ~= previous_x then result.motion_end = real end
    previous_x = window.x
    if state.phase == "flying" then
      local offset = direction * (window.x - x)
      result.peak = math.max(result.peak, offset)
      result.rebound = math.max(result.rebound, -offset)
      result.vmax = math.max(result.vmax, math.abs(state.ov))
      -- The first nudge and transition into a chain deliberately differ. Compare the
      -- established response from the fourth accepted switch onward.
      if result.accepted >= 4 then
        result.chain_vmax = math.max(result.chain_vmax, math.abs(state.ov))
      end
      result.error = math.max(result.error, math.abs(window.x - (state.home_x + module.config.lead * state.o)))
      result.outside = math.max(result.outside, world.monitor.x - window.x,
        window.x + width - world.monitor.x - world.monitor.width)
      result.intensity = math.max(result.intensity, state.inertia)
      assert(state.inertia >= 0 and state.inertia <= 1, "inertia escaped its bounds")
      assert(state.activity >= 0 and state.activity <= 1, "input activity escaped its bounds")
      assert(window.x == window.x and math.abs(window.x) < 1e7, "non-finite or runaway position")
      result.samples[#result.samples + 1] = window.x

      if presses[next_press] and real >= presses[next_press].at then
        local press = presses[next_press]
        local before = { state.h, state.hv, state.o, state.ov, state.dest }
        if press.target then module.press_to(press.target) else module.press(press.dir or direction) end
        assert(state.h == before[1] and state.hv == before[2] and state.o == before[3] and state.ov == before[4],
          "a press reset position or velocity")
        if state.dest ~= before[5] then result.accepted = result.accepted + 1; last_accepted = real end
        next_press = next_press + 1
      end
    elseif state.phase == "landing" then
      result.flight_after_last = result.flight_after_last or (real - last_accepted)
    elseif state.phase == "idle" then
      assert(window.x == x and window.y == 150, "did not finish at the exact home position")
      assert(not window.pinned and not window.no_anim, "carry overrides leaked")
      for _, timer in ipairs(world.timers) do assert(not timer.enabled, "timer stayed enabled") end
      -- A quiet nudge can land before the next slow press. Keep exercising the rest of
      -- that input sequence instead of reporting only its first completed flight.
      if presses[next_press] then
        if real >= presses[next_press].at then
          local press, previous = presses[next_press], window.workspace_id
          if press.target then module.press_to(press.target) else module.press(press.dir or direction) end
          if window.workspace_id ~= previous then result.accepted = result.accepted + 1; last_accepted = real end
          next_press = next_press + 1
        end
        goto continue
      end
      result.duration, result.after_last = real, real - last_accepted
      result.watchdog = false
      for _, line in ipairs(world.logs) do
        if line:find("watchdog", 1, true) then result.watchdog = true end
        assert(not line:find("error:", 1, true), line)
      end
      return result
    end
    ::continue::
  end
  error("flight did not finish")
end

local function sequence(spacing, count)
  local out = {}
  for i = 1, count - 1 do out[#out + 1] = { at = i * spacing } end
  return out
end

-- Previous rapid profile, retaining the same isolated-switch nudge and timing.
local function previous_profile(c)
  c.turn_ms = 130
  c.window_zeta, c.inertia.window_zeta = 0.90, 0.74
  c.inertia.window_throw, c.inertia.max_throw_px = math.huge, math.huge
end

local function same_trajectory(before, after)
  assert(after.duration == before.duration, "single-switch timing changed")
  assert(#after.samples == #before.samples, "single-switch flight length changed")
  for i, x in ipairs(before.samples) do
    assert(after.samples[i] == x, "single-switch trajectory changed")
  end
end

local single, rapid
test("single carry stays close to home from launch through landing", function()
  single = simulate()
  assert(single.peak >= 8 and single.peak <= 30, "single nudge is absent or displaces the window too far")
  assert(single.rebound <= 1, "single rebound is still visible")
  assert(single.vmax <= 220, "single launch/return is too fast")
  assert(single.motion_end >= 650 and single.motion_end <= 950, "single nudge settles too early or lingers")
  -- The resting window remains pinned until the native workspace render offset is
  -- subpixel. Distinguish its visible motion from releasing that ownership.
  assert(single.duration <= 1200, "resting carry kept its overrides too long")
  assert(not single.watchdog, "single carry hit the watchdog")
  same_trajectory(simulate({ config = previous_profile }), single)
  print(string.format("  single excursion: %d px; motion settles: %d ms; cleanup: %d ms",
    single.peak, single.motion_end, single.duration))
end)

test("single nudge scales with the window rather than the monitor", function()
  for _, width in ipairs({ 400, 800, 1200 }) do
    local reference
    for _, monitor_width in ipairs({ 1920, 3440, 5120, 7680 }) do
      for _, direction in ipairs({ -1, 1 }) do
        local flight = simulate({ width = width, monitor_width = monitor_width,
          x = (monitor_width - width) / 2, direction = direction })
        same_trajectory(simulate({ width = width, monitor_width = monitor_width,
          x = (monitor_width - width) / 2, direction = direction, config = previous_profile }), flight)
        assert(flight.peak <= math.min(30, width * 0.025), "nudge moved too far from home")
        assert(flight.rebound <= 1 and not flight.watchdog, "single landing was not quiet")
        if reference then assert(math.abs(flight.peak - reference) <= 1, "monitor width amplified the launch") end
        reference = flight.peak
      end
    end
  end
end)

test("same number of switches responds progressively to cadence", function()
  rapid = simulate({ presses = sequence(200, 4) })
  local medium = simulate({ presses = sequence(400, 4) })
  local slow = simulate({ presses = sequence(800, 4) })
  print(string.format("  single: %.0f px travel, %.0f px rebound; medium: %.0f/%.0f; rapid: %.0f px travel, %.0f px rebound, %.2fx peak speed",
    single.peak, single.rebound, medium.peak, medium.rebound,
    rapid.peak, rapid.rebound, rapid.vmax / single.vmax))
  assert(rapid.accepted == 4 and medium.accepted == 4 and slow.accepted == 4, "test sequence was not accepted")
  assert(rapid.vmax > single.vmax * 1.3, "fast switches did not build speed")
  assert(rapid.vmax < single.vmax * 1.6, "fast switches became too abrupt")
  assert(rapid.peak > medium.peak and medium.peak > slow.peak, "travel does not follow input cadence")
  assert(rapid.peak <= single.peak * 3, "fast outward movement is too dramatic")
  assert(rapid.rebound >= medium.rebound and medium.rebound >= slow.rebound, "rebound does not follow input cadence")
  assert(rapid.rebound <= 3, "fast rebound is too dramatic")
  assert(slow.rebound <= single.rebound + 1, "slow switches built unwanted rebound")
  assert(rapid.after_last < 1400 and not rapid.watchdog, "rapid chain ended abruptly or lingered")
end)

test("established rapid chains have subtler travel, speed and rebound", function()
  for _, spacing in ipairs({ 200, 300 }) do
    for _, count in ipairs({ 4, 8 }) do
      for _, direction in ipairs({ -1, 1 }) do
        local before = simulate({ direction = direction, presses = sequence(spacing, count), config = previous_profile })
        local after = simulate({ direction = direction, presses = sequence(spacing, count) })
        assert(before.accepted == count and after.accepted == count, "rapid input acceptance changed")
        assert(after.peak < before.peak * 0.75, "rapid travel remains too dramatic")
        -- Compare the whole flight: the old throw hits the edge limit sooner, which
        -- already suppresses its speed during the later switches of a leftward chain.
        assert(after.vmax < before.vmax * 0.65, "rapid movement remains too fast")
        assert(after.rebound <= math.max(1, before.rebound * 0.4), "rapid rebound remains too strong")
        assert(after.after_last < 1400 and not after.watchdog, "rapid settling lingered or snapped home")
      end
    end
  end
end)

test("rapid back-and-forth switching is also more restrained", function()
  for _, spacing in ipairs({ 300, 400 }) do
    local presses = {}
    for i = 1, 7 do presses[i] = { at = spacing * i, dir = i % 2 == 1 and -1 or 1 } end
    local before = simulate({ presses = presses, config = previous_profile })
    local after = simulate({ presses = presses })
    assert(before.accepted == 8 and after.accepted == 8, "back-and-forth sequence was not accepted")
    assert(after.chain_vmax < before.chain_vmax * 0.75, "rapid reversal remains too fast")
    assert(after.peak < before.peak * 0.75 and after.rebound < before.rebound * 0.75,
      "back-and-forth travel remains too dramatic")
    assert(after.after_last < 1400, "rapid reversal settling lingered")
    assert(after.outside == 0 and not after.watchdog, "rapid reversal was unstable")
  end
end)

test("ignored early repeats add no energy", function()
  local presses = {}
  for ms = 10, 100, 10 do presses[#presses + 1] = { at = ms } end
  local repeats = simulate({ presses = presses })
  assert(repeats.accepted == 1 and repeats.intensity == 0, "ignored repeats charged inertia")
  assert(#repeats.samples == #single.samples, "ignored repeats changed flight duration")
  for i, x in ipairs(single.samples) do assert(repeats.samples[i] == x, "ignored repeats changed the trajectory") end
end)

test("one numbered jump stays as gentle as one adjacent switch", function()
  local jump = simulate({ target = 8 })
  assert(jump.peak == single.peak and jump.rebound == single.rebound and jump.intensity == 0,
    "a single numbered jump was mistaken for a rapid sequence")
end)

test("rapid reversals preserve momentum and settle without a snap", function()
  local reversal = simulate({ presses = { { at = 300, dir = -1 }, { at = 650 }, { at = 950, dir = -1 } } })
  assert(reversal.accepted == 4, "reversal sequence was not accepted")
  assert(not reversal.watchdog and reversal.outside == 0, "reversal escaped bounds or hit watchdog")
  assert(reversal.error <= 0.500001, "reversal introduced pixel feedback")
end)

for _, period in ipairs({ 2.08, 4.7, 8, 12 }) do
  test("pixel error stays bounded with " .. period .. " ms timer callbacks", function()
    local flight = simulate({ clock = true, period = period, presses = sequence(300, 4) })
    assert(flight.error <= 0.500001, "pixel limiter generated motion outside the spring trajectory")
    assert(not flight.watchdog and flight.outside == 0, "slow callbacks destabilised the flight")
    assert(flight.rebound < 60, "slow callbacks exaggerated the rebound")
  end)
end

test("jitter and compositor stalls do not generate a second oscillation", function()
  local flight = simulate({ clock = true, period = { 2, 5, 8, 3, 25, 4, 12 }, presses = sequence(400, 4) })
  assert(flight.error <= 0.500001 and flight.outside == 0, "jitter produced rounding drift")
  assert(not flight.watchdog, "jitter exhausted the watchdog")
end)

test("XWayland timing retains the same motion", function()
  local flight = simulate({ xwayland = true, clock = true, period = 4.7, presses = sequence(300, 4) })
  assert(flight.error <= 0.500001 and flight.outside == 0 and not flight.watchdog, "XWayland motion was unstable")
end)

test("screen edges smoothly suppress recoil", function()
  for _, monitor_width in ipairs({ 1920, 5120 }) do
    for _, width in ipairs({ 400, monitor_width - 16 }) do
      for _, left in ipairs({ true, false }) do
        for _, direction in ipairs({ -1, 1 }) do
          local origin = -1920 -- exercise global coordinates as well as logical size
          local x = origin + (left and 8 or monitor_width - width - 8)
          local flight = simulate({ monitor_width = monitor_width, monitor_x = origin, width = width,
            x = x, direction = direction, clock = true, period = 4.7, presses = sequence(400, 4) })
          assert(flight.outside == 0 and not flight.watchdog, "edge flight escaped the monitor or hit the watchdog")
        end
      end
    end
  end
end)

test("long active chains renew the watchdog instead of snapping home", function()
  local flight = simulate({ presses = sequence(350, 9) }) -- workspace 1 through 10
  assert(flight.accepted == 9 and flight.duration > 3000,
    string.format("long chain accepted %d switches and lasted %.0f ms", flight.accepted, flight.duration))
  assert(not flight.watchdog and flight.after_last < 1400, "active input did not renew the watchdog")
end)

test("watchdog still limits a stalled final switch", function()
  local flight = simulate({ presses = sequence(300, 3), config = function(c)
    c.max_flight_ms, c.settle_px = 600, -1 -- prevent natural settling for this test
  end })
  assert(flight.accepted == 3 and flight.watchdog, "last switch escaped its watchdog")
  assert(flight.flight_after_last >= 600 and flight.flight_after_last < 650,
    "watchdog budget was not measured from the last accepted press")
end)

os.exit(failures == 0 and 0 or 1)
