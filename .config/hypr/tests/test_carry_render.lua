-- Offline render-handoff regressions. Lua's window.at excludes the workspace offset;
-- Hyprland v0.56.2 Renderer.cpp adds that offset only to UNPINNED windows.
-- Model the configured native slide independently of carry.physics, including a
-- frame-old render offset and /proc/uptime quantization. No compositor calls.
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
  world.monitor.width, world.monitor.scale = opts.width or 5120, opts.scale or 1
  local direction = opts.direction or 1
  world.active_workspace = direction == 1 and 1 or 10
  local backend = mock.new(world)
  local module = assert(loadfile(carry_path))()
  module.config.tick_scale = opts.tick_scale or 1
  local now, slide_start, side = opts.clock_phase or 0, 0, direction
  if not opts.no_clock then backend.clock_ms = function() return math.floor(now / 10) * 10 end end
  backend.workspace_gap = function() return opts.gap or 0 end
  local focus, pin = backend.focus_workspace, backend.pin
  local accepted, releases, last_release = 0, {}, nil
  local frame_ms = opts.frame_ms or (1000 / 60)

  -- Exact from-rest solution for native gentle: mass=1, stiffness=110, damping=20.
  -- Do not use the module's completion helper to predict renderer behavior.
  local function render_offset()
    local frame_time = math.floor(now / frame_ms) * frame_ms
    local t = math.max(0, frame_time - slide_start) / 1000
    local wd = math.sqrt(10)
    local displacement = math.exp(-10 * t) * (math.cos(wd * t) + 10 / wd * math.sin(wd * t))
    return side * (world.monitor.width + (opts.gap or 0)) * displacement
  end
  local function screen_x(addr)
    local w = world.windows[addr]
    return (w.x + (w.pinned and 0 or render_offset())) * world.monitor.scale
  end
  backend.focus_workspace = function(id)
    side = id > world.active_workspace and 1 or -1
    slide_start = now
    accepted = accepted + 1
    focus(id)
  end
  backend.pin = function(addr, on)
    local before = screen_x(addr)
    pin(addr, on)
    if not on then
      local jump = math.abs(screen_x(addr) - before)
      releases[#releases + 1], last_release = jump, now
    end
  end
  module.setup(backend)
  local home = math.floor((world.monitor.width - 1200) / 2)
  local addr = world:create_window({ x = home, y = 150, w = 1200, h = 800,
    workspace_id = world.active_workspace, xwayland = opts.xwayland })
  world:set_active(addr)
  module.press(direction)
  local presses, next_press, idle_at = opts.presses or {}, 1, nil
  local periods = opts.periods or { opts.xwayland and 4 or 2 }
  for tick = 1, 5000 do
    now = now + periods[(tick - 1) % #periods + 1]
    world:tick()
    if presses[next_press] and now >= presses[next_press].at then
      module.press(presses[next_press].dir or direction)
      next_press = next_press + 1
    end
    if last_release then
      assert(releases[#releases] <= 0.5,
        string.format("unpin added %.3f screen pixels at %.0f ms", releases[#releases], last_release))
      assert(math.abs(screen_x(addr) - home * world.monitor.scale) <= 0.5,
        "workspace spring moved the window after the handoff")
    end
    if module.state().phase == "idle" then
      idle_at = idle_at or now
      if now - idle_at >= 1000 then break end -- include the native spring's entire tail
    end
  end
  assert(idle_at and idle_at - slide_start < 1400, "handoff lingered or hit the watchdog")
  assert(accepted == #presses + 1 and #releases == 1, "carry sequence did not remain one continuous flight")
  local w = world.windows[addr]
  assert(not w.pinned and not w.no_anim and w.x == home and w.y == 150, "landing leaked state or moved home")
  for _, line in ipairs(world.logs) do
    assert(not line:find("watchdog", 1, true) and not line:find("error", 1, true), line)
  end
  return releases[1]
end

test("single ultrawide carry has no rendered jump when the pin is released", function()
  print(string.format("  rendered handoff: %.3f px", simulate()))
end)

test("handoff stays subpixel across monitor sizes, scaling, directions and frame rates", function()
  for _, width in ipairs({ 1920, 5120, 7680 }) do
    for _, scale in ipairs({ 1, 1.25, 2 }) do
      for _, direction in ipairs({ -1, 1 }) do
        for _, frame_ms in ipairs({ 1000 / 30, 1000 / 144 }) do
          simulate({ width = width, scale = scale, direction = direction, frame_ms = frame_ms })
        end
      end
    end
  end
end)

test("rapid carry chains wait for the final workspace slide", function()
  simulate({ presses = { { at = 200 }, { at = 400 }, { at = 600 } } })
end)

test("reversals and a carry near the old landing boundary remain continuous", function()
  simulate({ presses = { { at = 300, dir = -1 }, { at = 650 }, { at = 1600, dir = -1 } } })
end)

test("release follows native wall time when physics runs fast or timer cadence changes", function()
  for _, clock_phase in ipairs({ 0, 9 }) do
    simulate({ tick_scale = 2, clock_phase = clock_phase,
      periods = { 2, 2, 5, 10, 4, 8, 3, 40 }, gap = 300 })
  end
end)

test("native and XWayland nominal clocks also preserve the rendered handoff", function()
  simulate({ no_clock = true })
  simulate({ no_clock = true, xwayland = true })
end)

os.exit(failures == 0 and 0 or 1)
