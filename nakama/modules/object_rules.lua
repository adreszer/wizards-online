-- Server-authoritative state of world objects (doors, secret walls, switches,
-- torches, levers, statues). The object map comes from generated.world_objects
-- (exported from the castle scene); each kind has a small rule that turns a
-- validated event into a new state. Only discrete states live here; physics
-- objects (pushable blocks, pressure plates) stay local to each client.
--
-- States: secret_wall "revealed" | nil, magic_switch / lever true | false,
-- wall_torch lit true | false, rotating_statue 0..state_count-1. A missing
-- entry means the object's default, so snapshots only carry changed objects.

local OBJECTS = require("generated.world_objects")
local SPELLS = require("generated.spells")

local M = {}

M.EVENTS_PER_SECOND = 8
M.EVENT_BURST = 16
M.OBJECT_COOLDOWN = 0.3
M.MAX_ID_BYTES = 96

M.OBJECTS = OBJECTS

local function accepts(obj, effect_type)
  for _, t in ipairs(obj.accepts or {}) do
    if t == "any" or t == effect_type then
      return true
    end
  end
  return false
end

local function current(world, oid, default)
  local s = world.objects[oid]
  if s == nil then
    return default
  end
  return s
end

-- kind -> { spell = fn(world, oid, obj, effect_type) -> new state | nil,
--           interact = fn(world, oid, obj) -> new state | nil }
-- Returning nil means "no change"; the event is then dropped silently.
M.KINDS = {
  secret_wall = {
    spell = function(world, oid, obj)
      if world.objects[oid] == "revealed" then return nil end
      return "revealed"
    end,
  },
  magic_switch = {
    spell = function(world, oid, obj)
      local on = current(world, oid, false)
      if on and not obj.toggleable then return nil end
      return not on
    end,
  },
  wall_torch = {
    spell = function(world, oid, obj, effect_type)
      local lit = current(world, oid, obj.lit ~= false)
      if effect_type == "fire" and not lit then return true end
      if (effect_type == "water" or effect_type == "frost" or effect_type == "dark") and lit then return false end
      return nil
    end,
  },
  lever = {
    interact = function(world, oid, obj)
      local on = current(world, oid, false)
      if on and obj.one_shot then return nil end
      return not on
    end,
  },
  rotating_statue = {
    spell = function(world, oid, obj)
      local n = math.max(1, math.floor(obj.state_count or 4))
      local s = current(world, oid, math.floor(obj.initial_state or 0) % n)
      return (s + 1) % n
    end,
  },
}

function M.new_world()
  -- objects: oid -> state; relight: oid -> time; buckets: sid -> {tokens, at};
  -- last: oid -> time of the last change; driven: oid -> true for objects only
  -- mysteries may change (direct events are ignored).
  return { objects = {}, relight = {}, buckets = {}, last = {}, driven = {} }
end

local function take_token(world, sid, now)
  local b = world.buckets[sid]
  if not b then
    b = { tokens = M.EVENT_BURST, at = now }
    world.buckets[sid] = b
  end
  b.tokens = math.min(M.EVENT_BURST, b.tokens + (now - b.at) * M.EVENTS_PER_SECOND)
  b.at = now
  if b.tokens < 1 then
    return false
  end
  b.tokens = b.tokens - 1
  return true
end

local function in_reach(obj, area)
  for _, a in ipairs(obj.areas or { obj.area }) do
    if a == area then
      return true
    end
  end
  return false
end

-- Sets a state (from a rule or from a mystery) and schedules side effects.
-- Returns true when the state changed.
function M.set(world, oid, value, now)
  local obj = OBJECTS[oid]
  if not obj or world.objects[oid] == value then
    return false
  end
  world.objects[oid] = value
  world.last[oid] = now
  world.relight[oid] = nil
  if obj.kind == "wall_torch" then
    if value == true then
      world.objects[oid] = nil -- lit is the default
    elseif (obj.relight_after or 0) > 0 then
      world.relight[oid] = now + obj.relight_after
    end
  end
  return true
end

-- Validates a client event. `ctx` = { sid, area, knows = fn(spell_id) -> bool }.
-- Returns oid, new_state on success; nil, reason when refused.
function M.handle(world, ctx, payload, now)
  if type(payload) ~= "table" then return nil, "bad_payload" end
  local oid, event = payload.o, payload.e
  if type(oid) ~= "string" or #oid > M.MAX_ID_BYTES then return nil, "bad_object" end
  local obj = OBJECTS[oid]
  if not obj then return nil, "unknown_object" end
  if not take_token(world, ctx.sid, now) then return nil, "rate_limited" end
  if not in_reach(obj, ctx.area) then return nil, "out_of_reach" end
  if world.driven[oid] then return nil, "mystery_driven" end
  if world.last[oid] and now - world.last[oid] < M.OBJECT_COOLDOWN then return nil, "cooldown" end
  local rule = M.KINDS[obj.kind]
  if not rule then return nil, "static_kind" end
  local new_state
  if event == "spell" then
    local spell = payload.spell
    if type(spell) ~= "string" or not SPELLS.by_id[spell] then return nil, "unknown_spell" end
    if not ctx.knows(spell) then return nil, "spell_not_known" end
    local effect_type = SPELLS.by_id[spell].effect_type
    if not accepts(obj, effect_type) or not rule.spell then return nil, "not_accepted" end
    new_state = rule.spell(world, oid, obj, effect_type)
  elseif event == "interact" then
    if not rule.interact then return nil, "not_accepted" end
    new_state = rule.interact(world, oid, obj)
  else
    return nil, "bad_event"
  end
  if new_state == nil then return nil, "no_change" end
  M.set(world, oid, new_state, now)
  return oid, new_state
end

-- Timed changes due at `now` (torches relighting). Returns a list of {oid, state}.
function M.tick(world, now)
  local changes = {}
  for oid, at in pairs(world.relight) do
    if now >= at then
      world.relight[oid] = nil
      world.objects[oid] = nil
      world.last[oid] = now
      table.insert(changes, { oid, true })
    end
  end
  return changes
end

function M.forget_player(world, sid)
  world.buckets[sid] = nil
end

return M
