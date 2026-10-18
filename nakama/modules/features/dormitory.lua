-- Dormitories: every member of a house gets a bed in the house dormitory on their first
-- visit (beds are numbered; the client maps a number to a bed). Over the bed corner they
-- hang up to MAX_DECOR items they own and that are decor (pennant, star chart, trophy,
-- a potted plant…): the item stays in the inventory, the corner shows it to everyone who
-- comes by, with the owner's name on a plate.
--
-- Storage: school/dorm_<house> (system): { beds = { [uid] = { bed, name, decor = { id… } } }, next = n }
-- Push "dorm": { houses = { ["1"] = { [bed] = { name, decor } } } } to everyone.

local Store = require("store")

local M = { name = "dormitory" }

M.COLLECTION = "school"
M.MAX_DECOR = 3
M.MAX_BEDS = 64

local function load(house)
  local d = Store.read(M.COLLECTION, "dorm_" .. house, nil) or {}
  d.beds = type(d.beds) == "table" and d.beds or {}
  d.next = tonumber(d.next) or 1
  return d
end

local function cache(api)
  local f = api.state.features
  if not f.dorm then
    f.dorm = {}
    for h = 1, 4 do f.dorm[h] = load(h) end
  end
  return f.dorm
end

local function dorm_view(api)
  local houses = {}
  for h, d in pairs(cache(api)) do
    local beds = {}
    for _, b in pairs(d.beds) do beds[tostring(b.bed)] = { name = b.name, decor = b.decor } end
    houses[tostring(h)] = beds
  end
  return { houses = houses }
end

local function save(api, house)
  Store.write(M.COLLECTION, "dorm_" .. house, nil, cache(api)[house])
  api.push("dorm", dorm_view(api), nil)
end

-- The member's bed record, created on first need (nil without a house or room).
function M.bed_of(api, sid, create)
  local house, uid = api.house(sid), api.uid(sid)
  if house < 1 or not uid then return nil end
  local d = cache(api)[house]
  local b = d.beds[uid]
  if not b and create then
    if d.next > M.MAX_BEDS then return nil end
    b = { bed = d.next, name = api.name(sid), decor = {} }
    d.beds[uid] = b
    d.next = d.next + 1
    save(api, house)
  end
  return b
end

function M.join(api, sid)
  api.push("dorm", dorm_view(api), sid)
end

-- Walking into one's own dormitory claims a bed.
function M.area(api, sid, area)
  local def = api.AREAS[area]
  if def and def.kind == "dormitory" and def.house == api.house(sid) and def.house > 0 then
    M.bed_of(api, sid, true)
  end
end

M.requests = {}

-- {decor = [item ids]} the corner's decorations (owned decor items, at most MAX_DECOR).
M.requests.dorm_decorate = function(api, sid, payload)
  local b = M.bed_of(api, sid, true)
  if not b then return nil, "no_house" end
  local list = type(payload.decor) == "table" and payload.decor or {}
  if #list > M.MAX_DECOR then return nil, "too_many" end
  local clean, seen = {}, {}
  for _, id in ipairs(list) do
    local def = type(id) == "string" and api.ITEMS[id] or nil
    if not def or def.category ~= "decor" then return nil, "not_decor" end
    if api.count_item(sid, id) < 1 then return nil, "not_owned" end
    if not seen[id] then
      seen[id] = true
      table.insert(clean, id)
    end
  end
  b.decor = clean
  b.name = api.name(sid)
  save(api, api.house(sid))
  return { bed = b.bed, decor = clean }
end

return M
