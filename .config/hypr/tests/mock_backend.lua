-- mock_backend.lua
-- Offline virtual-compositor backend shared by the carry.lua regression suites.
-- Pure Lua, no hyprctl, no sockets.

local World = {}
World.__index = World

local M = {}

function M.new_world()
  local world = setmetatable({
    monitor = { id = 0, x = 0, y = 0, width = 5120, height = 1440, scale = 1 },
    windows = {},
    active_address = nil,
    active_workspace = 1,
    calls = {},
    timers = {},
    handlers = { ["window.close"] = {}, ["config.reloaded"] = {} },
    logs = {},
    trajectory = {},
    z_order = {},
    next_addr = 1,
  }, World)
  return world
end

-- opts: address, x, y, w, h, floating(default true), fullscreen(default 0),
--       pinned(default false), xwayland(default false), workspace_id(default 1)
function World:create_window(opts)
  opts = opts or {}
  local addr = opts.address
  if not addr then
    addr = "0x" .. tostring(self.next_addr)
    self.next_addr = self.next_addr + 1
  end
  self.windows[addr] = {
    address = addr,
    x = opts.x or 0,
    y = opts.y or 0,
    w = opts.w or 800,
    h = opts.h or 600,
    floating = (opts.floating ~= false),
    fullscreen = opts.fullscreen or 0,
    pinned = opts.pinned or false,
    xwayland = opts.xwayland or false,
    workspace_id = opts.workspace_id or 1,
    no_anim = false,
  }
  table.insert(self.z_order, addr)
  return addr
end

function World:window(addr)
  return self.windows[addr]
end

function World:set_active(addr)
  self.active_address = addr
end

function World:close(addr)
  local w = self.windows[addr]
  if not w then return end
  self.windows[addr] = nil
  for i, candidate in ipairs(self.z_order) do
    if candidate == addr then table.remove(self.z_order, i); break end
  end
  if self.active_address == addr then self.active_address = nil end
  for _, cb in ipairs(self.handlers["window.close"]) do
    cb({ address = w.address })
  end
end

function World:emit(event, ...)
  for _, cb in ipairs(self.handlers[event] or {}) do
    cb(...)
  end
end

-- Runs every enabled timer callback n times. After each individual tick,
-- snapshots every live window's {x,y} into world.trajectory (a list of
-- address -> {x=,y=} tables, one per tick).
function World:tick(n)
  n = n or 1
  for _ = 1, n do
    -- snapshot timers list at loop start so a timer disabling itself mid
    -- tick doesn't skip other timers, but does stop firing next tick
    for _, t in ipairs(self.timers) do
      if t.enabled then
        t.cb()
      end
    end
    local snap = {}
    for addr, w in pairs(self.windows) do
      snap[addr] = { x = w.x, y = w.y }
    end
    table.insert(self.trajectory, snap)
  end
end

-- Returns the list of {x,y} positions recorded for `addr` across all ticks
-- in which the window was alive (in creation/tick order).
function World:trajectory_for(addr)
  local out = {}
  for _, snap in ipairs(self.trajectory) do
    if snap[addr] then table.insert(out, snap[addr]) end
  end
  return out
end

-- Returns calls matching `op` (and optionally a matching `address`), in order.
function World:calls_matching(op, address)
  local out = {}
  for _, c in ipairs(self.calls) do
    if c.op == op and (address == nil or c.address == address) then
      table.insert(out, c)
    end
  end
  return out
end

local function copy_window(w, monitor)
  return {
    address = w.address, x = w.x, y = w.y, w = w.w, h = w.h,
    floating = w.floating, fullscreen = w.fullscreen, pinned = w.pinned,
    xwayland = w.xwayland, workspace_id = w.workspace_id,
    monitor = monitor,
  }
end

-- Builds the carry.lua backend table, closed over `world`.
function M.new(world)
  local backend = {}

  function backend.active_window()
    local addr = world.active_address
    if not addr then return nil end
    local w = world.windows[addr]
    if not w then return nil end
    return copy_window(w, world.monitor)
  end

  function backend.get_window(address)
    local w = world.windows[address]
    if not w then return nil end
    return copy_window(w, world.monitor)
  end

  function backend.active_workspace_id()
    return world.active_workspace
  end

  function backend.pin(address, bool)
    local w = world.windows[address]
    if w and w.pinned ~= bool then
      w.pinned = bool
      -- Native pin/unpin assigns the active workspace; disabling an already-disabled
      -- pin is a no-op. This matters when a carry finishes on a hidden workspace.
      w.workspace_id = world.active_workspace
    end
    table.insert(world.calls, { op = "pin", address = address, value = bool })
  end

  function backend.set_no_anim(address, bool)
    local w = world.windows[address]
    if w then w.no_anim = bool end
    table.insert(world.calls, { op = "set_no_anim", address = address, value = bool })
  end

  function backend.move_to(address, x, y)
    local w = world.windows[address]
    if w then w.x = x; w.y = y end
    table.insert(world.calls, { op = "move_to", address = address, x = x, y = y })
  end

  function backend.raise_window(address)
    for i, candidate in ipairs(world.z_order) do
      if candidate == address then table.remove(world.z_order, i); break end
    end
    table.insert(world.z_order, address)
    table.insert(world.calls, { op = "raise_window", address = address })
  end

  -- Hyprland reassigns pinned windows to the workspace focused.
  function backend.focus_workspace(id)
    local previous = world.active_workspace
    world.active_workspace = id
    for _, w in pairs(world.windows) do
      if w.pinned and w.workspace_id == previous then w.workspace_id = id end
    end
    local active = world.active_address and world.windows[world.active_address]
    if active and not active.pinned and active.workspace_id ~= id then
      world.active_address = nil
      for other, candidate in pairs(world.windows) do
        if candidate.workspace_id == id then world.active_address = other; break end
      end
    end
    table.insert(world.calls, { op = "focus_workspace", id = id })
    world:emit("workspace.active", { id = id, monitor = world.monitor })
  end

  function backend.move_window_to_workspace(address, id)
    local w = world.windows[address]
    if w then w.workspace_id = id end
    table.insert(world.calls, { op = "move_window_to_workspace", address = address, id = id })
    if world.active_address == address and id ~= world.active_workspace then
      world.active_address = nil
      for other, candidate in pairs(world.windows) do
        if candidate.workspace_id == world.active_workspace then world.active_address = other; break end
      end
    end
  end

  function backend.move_window_to_workspace_follow(id)
    local addr = world.active_address
    local w = addr and world.windows[addr]
    if w then w.workspace_id = id end
    table.insert(world.calls, { op = "move_window_to_workspace_follow", id = id })
  end

  function backend.timer(callback, ms)
    local t = { cb = callback, ms = ms, enabled = true }
    function t:set_enabled(b) self.enabled = b end
    function t:is_enabled() return self.enabled end
    table.insert(world.timers, t)
    table.insert(world.calls, { op = "timer", ms = ms })
    return t
  end

  function backend.on(event, cb)
    world.handlers[event] = world.handlers[event] or {}
    table.insert(world.handlers[event], cb)
  end

  function backend.log(msg)
    table.insert(world.logs, msg)
  end

  return backend
end

return M
