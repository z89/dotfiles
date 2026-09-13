-- Offline workspace-ownership regressions; no compositor calls.
-- CARRY optionally selects an unwatched candidate module.
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

local function fixture()
  local world = mock.new_world()
  local backend = mock.new(world)
  local module = assert(loadfile(carry_path))()
  module.setup(backend)
  local addr = world:create_window({ x = 1400, y = 150, w = 1200, h = 800, workspace_id = 1 })
  local other = world:create_window({ x = 100, y = 100, w = 600, h = 500, workspace_id = 1 })
  world:set_active(addr)
  module.press(1)
  return module, world, backend, addr, other
end

local function until_phase(module, world, phase)
  for _ = 1, 2000 do
    if module.state().phase == phase then return end
    world:tick(1)
  end
  error("did not reach " .. phase)
end

local function check_landed(module, world, addr, destination, viewed)
  until_phase(module, world, "idle")
  local window = world.windows[addr]
  assert(window.workspace_id == destination, "landed on the workspace being viewed")
  assert(window.x == 1400 and window.y == 150, "landing changed the original home")
  assert(not window.pinned and not window.no_anim, "carry overrides leaked")
  assert(world.active_workspace == viewed, "carry stole the user's workspace")
  for _, timer in ipairs(world.timers) do assert(not timer.enabled, "timer remained enabled") end
end

local late_tick = 0
do
  local module, world = fixture()
  while module.state().phase == "flying" and late_tick < 2000 do world:tick(1); late_tick = late_tick + 1 end
  assert(module.state().phase == "landing", "could not locate late flight")
  late_tick = late_tick - 1
  module.land("test calibration")
end

for _, ticks in ipairs({ 1, math.floor(late_tick / 2), late_tick }) do
  test("ordinary navigation preserves destination at tick " .. ticks, function()
    local module, world, backend, addr, other = fixture()
    world:tick(ticks)
    local state = module.state()
    local before = { state.h, state.hv, state.o, state.ov, state.t }
    local x = world.windows[addr].x
    backend.focus_workspace(1)
    assert(state.phase == "flying" and state.dest == 2, "navigation interrupted or redirected flight")
    assert(state.h == before[1] and state.hv == before[2] and state.o == before[3]
      and state.ov == before[4] and state.t == before[5], "navigation reset the physics")
    assert(world.windows[addr].workspace_id == 2 and not world.windows[addr].pinned,
      "window followed ordinary navigation")
    assert(world.windows[addr].x == x and world.windows[addr].no_anim, "navigation snapped or ended the motion")
    assert(world.active_address == other, "hidden carried window kept focus")
    local calls = #world:calls_matching("focus_workspace")
    check_landed(module, world, addr, 2, 1)
    assert(#world:calls_matching("focus_workspace") == calls, "landing changed workspace focus")
    assert(world.windows[other].workspace_id == 1 and world.windows[other].x == 100, "unrelated window moved")
  end)
end

test("repeated navigation cannot reattach the carried window", function()
  local module, world, backend, addr = fixture()
  world:tick(50)
  for _, ws in ipairs({ 1, 3, 2, 1, 4, 2, 1 }) do
    backend.focus_workspace(ws)
    world:tick(20)
    assert(world.windows[addr].workspace_id == 2 and not world.windows[addr].pinned, "navigation reattached carry")
  end
  check_landed(module, world, addr, 2, 1)
end)

test("navigation during landing leaves the destination intact", function()
  local module, world, backend, addr = fixture()
  until_phase(module, world, "landing")
  backend.focus_workspace(1)
  assert(module.state().phase == "landing" and world.windows[addr].workspace_id == 2, "landing followed navigation")
  check_landed(module, world, addr, 2, 1)
end)

test("normal carry preserves stack order when returning to the floating layer", function()
  local module, world, _, addr, other = fixture()
  world.windows[other].workspace_id = 2
  local release_tick
  for tick = 1, 2000 do
    world:tick(1)
    if not world.windows[addr].pinned then release_tick = tick; break end
  end
  assert(release_tick and module.state().phase == "landing", "pin release did not complete the flight")
  assert(world.z_order[#world.z_order] == addr, "carried window lost its visible stack position")
  assert(world.active_address == addr, "restoring stack order changed keyboard focus")

  local pin_call
  for i, call in ipairs(world.calls) do
    if call.op == "pin" and call.value == false then pin_call = i end
  end
  assert(pin_call and world.calls[pin_call + 1].op == "move_to",
    "unpin layout movement was not corrected in the same callback")
  assert(world.calls[pin_call + 2].op == "raise_window",
    "floating stack order was not restored with the position")

  local raises = #world:calls_matching("raise_window", addr)
  check_landed(module, world, addr, 2, 2)
  assert(#world:calls_matching("raise_window", addr) == raises,
    "the finish boundary changed stack order a second time")
end)

test("a synchronous unpin refit never reaches a rendered tick", function()
  local module, world, backend, addr = fixture()
  local native_pin = backend.pin
  backend.pin = function(address, on)
    native_pin(address, on)
    if not on then world.windows[address].x = world.windows[address].x + 300 end
  end
  for _ = 1, 2000 do
    world:tick(1)
    if not world.windows[addr].pinned then break end
  end
  local state = module.state()
  assert(state.phase == "landing" and world.windows[addr].x == state.home_x,
    "unpin refit escaped the release callback as a visible position")
  check_landed(module, world, addr, 2, 2)
end)

test("landing observes several compositor frames before clearing no_anim", function()
  local module, world, _, addr = fixture()
  until_phase(module, world, "landing")
  world:tick(module.config.land_min_ticks - 1)
  assert(module.state().phase == "landing" and world.windows[addr].no_anim,
    "landing released its override before the observation window")
  world:tick(1)
  assert(module.state().phase == "idle" and not world.windows[addr].no_anim,
    "stable landing did not finish after the observation window")
end)

test("landing repairs layout work arriving after the old three-tick window", function()
  local module, world, _, addr = fixture()
  until_phase(module, world, "landing")
  world:tick(10)
  assert(module.state().phase == "landing", "landing ended before delayed layout work")
  world.windows[addr].x = world.windows[addr].x + 7
  world:tick(2)
  assert(module.state().land_bias_x == -7, "delayed layout position was not corrected")
  check_landed(module, world, addr, 2, 2)
end)

test("timer repairs a missed workspace event", function()
  local module, world, backend, addr = fixture()
  world:tick(100)
  world.handlers["workspace.active"] = {}
  backend.focus_workspace(1)
  assert(world.windows[addr].workspace_id == 1, "test did not reproduce pinned reassignment")
  world:tick(1)
  assert(module.state().phase == "flying" and world.windows[addr].workspace_id == 2, "timer failed to restore destination")
  check_landed(module, world, addr, 2, 1)
end)

test("a transient workspace correction failure retries without ending the flight", function()
  local module, world, backend, addr = fixture()
  world:tick(100)
  local move, failed = backend.move_window_to_workspace, false
  backend.move_window_to_workspace = function(address, ws)
    if not failed then failed = true; error("temporary move failure") end
    return move(address, ws)
  end
  backend.focus_workspace(1)
  assert(module.state().phase == "flying" and world.windows[addr].no_anim, "failed correction cancelled flight")
  world:tick(1)
  assert(world.windows[addr].workspace_id == 2 and module.state().phase == "flying", "correction did not retry")
  check_landed(module, world, addr, 2, 1)
end)

test("reload cleanup preserves destination even before a missed-event tick", function()
  local module, world, backend, addr = fixture()
  world.handlers["workspace.active"] = {}
  backend.focus_workspace(1)
  world:emit("config.reloaded")
  check_landed(module, world, addr, 2, 1)
end)

test("a carry shortcut can explicitly retarget the same flight", function()
  local module, world, _, addr = fixture()
  world:tick(150)
  module.press(-1)
  assert(module.state().phase == "flying" and module.state().dest == 1, "carry reversal was blocked")
  check_landed(module, world, addr, 1, 1)
end)

test("a new carry command can resume a detached flight", function()
  local module, world, backend, addr = fixture()
  world:tick(150)
  backend.focus_workspace(1)
  backend.focus_workspace(2)
  world:set_active(addr)
  local state, old_offset = module.state(), module.state().o
  module.press(-1)
  assert(state.dest == 1 and state.o == old_offset and not state.detached, "carry command did not retain and retarget flight")
  assert(world.windows[addr].pinned, "explicit carry did not resume workspace travel")
  check_landed(module, world, addr, 1, 1)
end)

test("carrying another window lands the previous one on its own destination", function()
  local module, world, backend, addr, other = fixture()
  world:tick(100)
  backend.focus_workspace(1)
  world:set_active(other)
  module.press_to(3)
  assert(world.windows[addr].workspace_id == 2 and world.windows[addr].x == 1400,
    "superseded carry landed on the viewed workspace")
  assert(not world.windows[addr].pinned and not world.windows[addr].no_anim, "superseded carry leaked overrides")
  assert(module.state().addr == other and module.state().dest == 3, "carry shortcut did not target the selected window")
  until_phase(module, world, "idle")
  assert(world.windows[other].workspace_id == 3 and world.windows[other].x == 100, "new carry did not land normally")
end)

test("dragging another window does not interrupt a detached carry", function()
  local module, world, backend, addr, other = fixture()
  world:tick(100)
  backend.focus_workspace(1)
  world:set_active(other)
  module.manual_control(272, true)
  assert(module.state().phase == "flying", "unrelated drag interrupted carry")
  world.windows[other].x = 220
  check_landed(module, world, addr, 2, 1)
  assert(world.windows[other].x == 220, "carry fought an unrelated drag")
  module.manual_control(272, false)
end)

test("dragging the carried window still takes over immediately", function()
  local module, world, backend, addr = fixture()
  world:tick(100)
  backend.focus_workspace(1)
  backend.focus_workspace(2)
  world:set_active(addr)
  local x = world.windows[addr].x
  module.manual_control(272, true)
  assert(module.state().phase == "idle" and not world.windows[addr].no_anim, "manual handoff was blocked")
  world.windows[addr].x = x + 100
  world:tick(200)
  assert(world.windows[addr].x == x + 100, "animation fought the mouse")
end)

test("manual handoff does not depend on keyboard focus catching up", function()
  local module, world, _, addr, other = fixture()
  world:tick(100)
  world.windows[other].workspace_id = 2
  world:set_active(other) -- native drag will choose the window under the pointer
  module.manual_control(272, true)
  assert(module.state().phase == "idle" and not world.windows[addr].no_anim,
    "stale keyboard focus blocked the immediate mouse handoff")
end)

test("mouse input on another workspace cannot cancel landing correction", function()
  local module, world, backend, addr = fixture()
  until_phase(module, world, "landing")
  world.windows[addr].x = world.windows[addr].x + 1
  backend.focus_workspace(1)
  module.manual_control(272, true)
  assert(module.state().phase == "landing", "unrelated mouse input abandoned landing")
  check_landed(module, world, addr, 2, 1)
  module.manual_control(272, false)
end)

test("unrelated workspace events leave the flight alone", function()
  local module, world, _, addr = fixture()
  local calls = #world.calls
  world:emit("workspace.active", { id = 8, monitor = { id = 1 } })
  assert(#world.calls == calls and module.state().dest == 2 and world.windows[addr].pinned,
    "an unrelated monitor changed the carry")
  check_landed(module, world, addr, 2, 2)
end)

test("closing a detached window leaves no stale movement", function()
  local module, world, backend, addr = fixture()
  backend.focus_workspace(1)
  world:close(addr)
  local calls = #world.calls
  world:tick(100)
  assert(module.state().phase == "idle" and #world.calls == calls, "closed carry kept dispatching")
end)

os.exit(failures == 0 and 0 or 1)
