-- Care of Magical Creatures and familiars. Three kinds of original creatures live in the
-- paddock (mosslings, emberkits, glimmerwings). A student there feeds one (a creature
-- treat, used up) or pets it, at most once a minute per kind; each builds their bond
-- with that kind. With a bond of ADOPT_BOND a creature follows them home: the familiar
-- (an item). A student who owns familiars picks one to walk with them; everyone sees it.
--
-- Storage: school/creatures per user (owner-readable): { bond = { [kind] = n }, familiar = kind | "" }
-- Push "creatures": { bond, familiar } to the student; "familiars": { [name] = kind } to everyone.

local Store = require("store")
local Wing = require("features.wing")

local M = { name = "creatures" }

M.COLLECTION, M.KEY = "school", "creatures"
M.AREA = "paddock"
M.KINDS = { mossling = true, emberkit = true, glimmerwing = true }
M.CARE_GAP = 60
M.ADOPT_BOND = 6
M.FEED_BOND, M.PET_BOND = 2, 1

local function cache(api)
  api.state.features.creature_rec = api.state.features.creature_rec or {}
  return api.state.features.creature_rec
end

local function familiars(api)
  api.state.features.familiars = api.state.features.familiars or {}
  return api.state.features.familiars
end

local function familiar_view(api)
  local out = {}
  for s, kind in pairs(familiars(api)) do
    if api.online(s) and kind ~= "" then out[api.name(s)] = kind end
  end
  return out
end

local function rec(api, sid)
  local c = cache(api)
  if not c[sid] then
    local r = Store.read(M.COLLECTION, M.KEY, api.uid(sid)) or {}
    r.bond = type(r.bond) == "table" and r.bond or {}
    r.familiar = type(r.familiar) == "string" and r.familiar or ""
    r.cared = {}
    c[sid] = r
  end
  return c[sid]
end

local function save(api, sid)
  local r = rec(api, sid)
  Store.write(M.COLLECTION, M.KEY, api.uid(sid), { bond = r.bond, familiar = r.familiar }, true)
  api.push("creatures", { bond = r.bond, familiar = r.familiar }, sid)
end

function M.join(api, sid)
  local r = rec(api, sid)
  if r.familiar ~= "" and api.count_item(sid, "familiar_" .. r.familiar) > 0 then familiars(api)[sid] = r.familiar end
  api.push("creatures", { bond = r.bond, familiar = r.familiar }, sid)
  api.push("familiars", familiar_view(api), nil)
end

function M.leave(api, sid)
  cache(api)[sid] = nil
  if familiars(api)[sid] then
    familiars(api)[sid] = nil
    api.push("familiars", familiar_view(api), nil)
  end
end

local function care(api, sid, kind, bond)
  if not M.KINDS[kind] then return nil, "unknown_creature" end
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local r = rec(api, sid)
  if r.cared[kind] and api.now - r.cared[kind] < M.CARE_GAP then return nil, "too_soon" end
  r.cared[kind] = api.now
  r.bond[kind] = (tonumber(r.bond[kind]) or 0) + bond
  save(api, sid)
  Wing.contribute(api, 1)
  return { kind = kind, bond = r.bond[kind], can_adopt = r.bond[kind] >= M.ADOPT_BOND }
end

M.requests = {}

M.requests.creature_feed = function(api, sid, payload)
  local kind = tostring(payload.kind or "")
  if not M.KINDS[kind] then return nil, "unknown_creature" end
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  if api.count_item(sid, "creature_treat") < 1 then return nil, "no_treats" end
  local r, why = care(api, sid, kind, M.FEED_BOND)
  if r then api.take_item(sid, "creature_treat", 1) end
  return r, why
end

M.requests.creature_pet = function(api, sid, payload)
  return care(api, sid, tostring(payload.kind or ""), M.PET_BOND)
end

M.requests.creature_adopt = function(api, sid, payload)
  local kind = tostring(payload.kind or "")
  if not M.KINDS[kind] then return nil, "unknown_creature" end
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local r = rec(api, sid)
  if (tonumber(r.bond[kind]) or 0) < M.ADOPT_BOND then return nil, "bond_too_weak" end
  local why = api.give_item(sid, "familiar_" .. kind)
  if why then return nil, why end
  r.familiar = kind
  familiars(api)[sid] = kind
  save(api, sid)
  api.push("familiars", familiar_view(api), nil)
  return { kind = kind }
end

-- {kind | ""}: which owned familiar walks with you ("" = none).
M.requests.familiar_set = function(api, sid, payload)
  local kind = tostring(payload.kind or "")
  if kind ~= "" and (not M.KINDS[kind] or api.count_item(sid, "familiar_" .. kind) < 1) then return nil, "not_owned" end
  local r = rec(api, sid)
  r.familiar = kind
  familiars(api)[sid] = kind ~= "" and kind or nil
  save(api, sid)
  api.push("familiars", familiar_view(api), nil)
  return { kind = kind }
end

return M
