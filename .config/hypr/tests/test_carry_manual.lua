-- Offline regression tests: lua5.5 ~/.config/hypr/tests/test_carry_manual.lua
-- CARRY and HYPR_CONFIG optionally select staged sources. No compositor calls.
local here = arg[0]:match("(.*/)") or "./"
package.path = here .. "?.lua;" .. package.path
local mock = require("mock_backend")
local carry_path = os.getenv("CARRY") or here .. "../carry.lua"
local config_path = os.getenv("HYPR_CONFIG") or here .. "../hyprland.lua"
local failures = 0

local function check(condition, message)
  assert(condition, message)
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then failures = failures + 1 end
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
end

local function fixture()
  local world = mock.new_world()
  local backend = mock.new(world)
  local module = assert(loadfile(carry_path))()
  module.setup(backend)
  local addr = world:create_window({ x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 })
  world:set_active(addr)
  return module, world, addr, backend
end

local function run_until(module, world, phase)
  for _ = 1, 2000 do
    if module.state().phase == phase then return end
    world:tick(1)
  end
  error("did not reach " .. phase)
end

local function check_handoff(module, world, addr, button)
  local window = world.windows[addr]
  local x, y = window.x, window.y
  local moves = #world:calls_matching("move_to", addr)
  module.manual_control(button, true)
  check(module.state().phase == "idle", "animation still owns the window")
  check(not window.pinned and not window.no_anim, "carry overrides leaked")
  check(window.x == x and window.y == y, "handoff snapped to the old home")
  check(#world:calls_matching("move_to", addr) == moves, "handoff issued a position correction")

  local calls = #world.calls
  for i = 1, 20 do
    -- A real mouse event is followed by several Lua timer opportunities per frame.
    window.x, window.y = x + 10 * i, y + 3 * i
    world:tick(4)
    check(window.x == x + 10 * i and window.y == y + 3 * i, "animation fought the mouse")
  end
  check(#world.calls == calls, "timer dispatched after handoff")
  -- A callback queued just before the timer was stopped is harmless too.
  for _, timer in ipairs(world.timers) do
    check(not timer.enabled, "timer remained enabled")
    timer.cb()
  end
  check(#world.calls == calls, "stale tick wrote after handoff")
end

-- Measure the last flying tick so late-grab coverage survives motion tuning.
local late_tick = 0
do
  local module, world = fixture()
  module.press(1)
  while module.state().phase == "flying" and late_tick < 2000 do
    world:tick(1)
    late_tick = late_tick + 1
  end
  check(module.state().phase == "landing", "could not locate the end of the flight")
  late_tick = late_tick - 1
  module.land("test calibration")
end

for _, ticks in ipairs({ 1, math.floor(late_tick / 2), late_tick }) do
  test("drag interrupts flight at tick " .. ticks, function()
    local module, world, addr = fixture()
    module.press(1)
    world:tick(ticks)
    check(module.state().phase == "flying", "test missed the flight")
    check_handoff(module, world, addr, 272)
  end)
end

test("drag interrupts landing correction", function()
  local module, world, addr = fixture()
  module.press(1)
  run_until(module, world, "landing")
  -- Simulate the existing layout nudge so the landing has a nonzero bias.
  world.windows[addr].x = world.windows[addr].x + 1
  world:tick(2)
  check(module.state().land_bias_x ~= 0, "test did not exercise landing bias")
  local pins = #world:calls_matching("pin", addr)
  check_handoff(module, world, addr, 272)
  check(#world:calls_matching("pin", addr) == pins, "landing handoff unnecessarily unpinned again")
end)

test("resize interrupts landing and retains the new size", function()
  local module, world, addr = fixture()
  module.press(1)
  run_until(module, world, "landing")
  check_handoff(module, world, addr, 273)
  local window = world.windows[addr]
  window.w, window.h = 1500, 900
  world:tick(100)
  check(window.w == 1500 and window.h == 900, "resize was overwritten")
end)

test("both held buttons block carry until the last release", function()
  local module, world, addr = fixture()
  module.press(1)
  world:tick(late_tick)
  module.manual_control(272, true)
  module.manual_control(273, true)
  local calls = #world.calls
  module.press(1)
  module.press_to(7)
  module.manual_control(272, false)
  module.press(-1)
  check(#world.calls == calls, "carry restarted during mouse control")
  module.manual_control(273, false)
  module.press_to(7)
  check(module.state().phase == "flying" and module.state().dest == 7, "last release did not re-enable carry")
end)

test("next carry uses the manually chosen home", function()
  local module, world, addr = fixture()
  module.press(1)
  world:tick(late_tick)
  module.manual_control(272, true)
  world.windows[addr].x, world.windows[addr].y = 1700, 230
  module.manual_control(272, false)
  module.press(1)
  run_until(module, world, "idle")
  local window = world.windows[addr]
  check(window.x == 1700 and window.y == 230, "next flight reused the old home")
  check(window.workspace_id == 3 and not window.pinned and not window.no_anim, "next flight did not complete normally")
end)

test("idle mouse interaction blocks carry without touching a window", function()
  local module, world = fixture()
  module.manual_control(272, true)
  module.manual_control(272, true)
  module.press(1)
  check(#world.calls == 0, "idle mouse hold touched the compositor")
  module.manual_control(272, false)
  module.manual_control(272, false)
  module.press(1)
  check(module.state().phase == "flying", "duplicate release left a stale hold")
end)

test("vanished window is not dispatched at during handoff", function()
  local module, world, addr = fixture()
  module.press(1)
  world.windows[addr] = nil -- close event has not arrived yet
  local calls = #world.calls
  module.manual_control(272, true)
  world:tick(20)
  check(#world.calls == calls, "handoff dispatched at a dead window")
  check(module.state().phase == "idle", "dead window left an active flight")
end)

test("cleanup still clears no_anim if unpin throws", function()
  local module, world, addr, backend = fixture()
  module.press(1)
  backend.pin = function() error("window changed during unpin") end
  module.manual_control(272, true)
  check(not world.windows[addr].no_anim, "unpin failure skipped clearing no_anim")
  check(module.state().phase == "idle" and not world.timers[1].enabled, "unpin failure left the timer running")
end)

-- Load the real config into an isolated Lua environment. File reads are intercepted,
-- startup/event callbacks never run, and every native dispatcher is a recording stub.
local function bindings(with_carry)
  local binds, events = {}, {}
  local function namespace(path)
    return setmetatable({}, {
      __index = function(_, key) return namespace(path .. "." .. key) end,
      __call = function() return function() events[#events + 1] = path end end,
    })
  end
  local stub = {
    setup = function() end, press = function() end, press_to = function() end,
    manual_control = function(button, pressed)
      events[#events + 1] = tostring(button) .. ":" .. tostring(pressed)
    end,
  }
  local env = setmetatable({ __test_carry = stub }, { __index = _G })
  env._G = env
  env.hl = setmetatable({
    dsp = namespace("dsp"),
    bind = function(key, action, opts)
      binds[#binds + 1] = { key = key, action = action, opts = opts or {} }
    end,
  }, { __index = function() return function() end end })
  env.os = { getenv = function() return "/test-home" end }
  env.io = { open = function(path)
    if with_carry and path == "/test-home/.config/hypr/carry.lua" then
      return { read = function() return "return __test_carry" end, close = function() end }
    end
  end }
  env.load = function(text, name) return load(text, name, "t", env) end
  assert(loadfile(config_path, "t", env))()
  return binds, events
end

test("mouse press hands off before the unchanged native move/resize bindings", function()
  local binds, events = bindings(true)
  for _, button in ipairs({ 272, 273 }) do
    local count, before = 0, #events
    for _, bind in ipairs(binds) do
      if bind.key == "SUPER + mouse:" .. button and not bind.opts.release then
        count = count + 1
        if count == 1 then check(bind.opts.non_consuming, "handoff consumes native mouse input") end
        if count == 2 then check(bind.opts.mouse, "native mouse binding was replaced") end
        bind.action()
      end
    end
    check(count == 2, "missing handoff or native binding")
    check(events[before + 1] == button .. ":true", "native drag began before carry stopped")
    check(events[before + 2] == (button == 272 and "dsp.window.drag" or "dsp.window.resize"), "wrong native dispatcher")
  end
end)

test("mouse release clears the hold even when Super was released first", function()
  local binds, events = bindings(true)
  for _, button in ipairs({ 272, 273 }) do
    local count = 0
    for _, bind in ipairs(binds) do
      if bind.key == "mouse:" .. button and bind.opts.release then
        count = count + 1
        check(bind.opts.ignore_mods and bind.opts.non_consuming, "release depends on modifiers or consumes input")
        bind.action()
        check(events[#events] == button .. ":false", "release cleared the wrong hold")
      end
    end
    check(count == 1, "missing release binding")
  end
end)

test("module load failure preserves ordinary mouse bindings", function()
  local binds = bindings(false)
  local count = 0
  for _, bind in ipairs(binds) do
    if bind.key:match("mouse:27[23]$") then
      count = count + 1
      check(bind.opts.mouse and not bind.opts.release, "fallback installed carry callbacks")
    end
  end
  check(count == 2, "fallback lost ordinary mouse bindings")
end)

os.exit(failures == 0 and 0 or 1)
