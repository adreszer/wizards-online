-- Arcane fragments a character has picked up, kept on the server so a fragment
-- stays collected after a relog or a server restart (storage "fragments"/"collected",
-- {ids = {object id = true}}). The client asks with fragment_collect {o} as it picks
-- one up; the server checks the object is a fragment and that the player stands
-- within REACH of it, and on join pushes "fragments" {ids} so the client hides
-- the ones already taken.

local Store = require("store")
local WORLD_OBJECTS = require("generated.world_objects")

local M = { name = "fragments" }

M.REACH = 6.0

local function load(uid)
  local saved = Store.read("fragments", "collected", uid)
  return saved and type(saved.ids) == "table" and saved.ids or {}
end

local function list(ids)
  local out = {}
  for id, _ in pairs(ids) do table.insert(out, id) end
  table.sort(out)
  return out
end

function M.join(api, sid)
  local uid = api.uid(sid)
  if uid then api.push("fragments", { ids = list(load(uid)) }, sid) end
end

M.requests = {}

M.requests.fragment_collect = function(api, sid, payload)
  local oid = type(payload.o) == "string" and payload.o or ""
  local def = WORLD_OBJECTS[oid]
  if not def or def.kind ~= "collectible" then return nil, "unknown_object" end
  local uid = api.uid(sid)
  if not uid then return nil, "offline" end
  local pos = api.position(sid)
  if pos and def.pos then
    local dx, dy, dz = pos[1] - def.pos[1], pos[2] - def.pos[2], pos[3] - def.pos[3]
    if dx * dx + dy * dy + dz * dz > M.REACH * M.REACH then return nil, "too_far" end
  end
  local ids = load(uid)
  if ids[oid] then return { count = #list(ids), already = true } end
  ids[oid] = true
  Store.write("fragments", "collected", uid, { ids = ids })
  return { count = #list(ids) }
end

return M
