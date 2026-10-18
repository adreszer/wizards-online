-- Herbology gardening: the greenhouse has PLOTS beds anyone may use. A student plants
-- a seed they own in a free bed, waters it (only watered plants grow), and harvests it
-- once grown: two of the herb. Quicksprout (a growth spell) cast on a watered plant
-- makes it ripe at once. Only the planter harvests their bed for a day; after that an
-- abandoned ripe plant may be picked by anyone. Harvests add to the Unfinished Wing.
--
-- Storage: school/garden (system): { plots = { [n] = { owner, name, seed, watered_at?, ready_at? } } }
-- Push "garden": { plots = { [n] = { name, seed, watered, ready, ready_at } } } to everyone.

local Store = require("store")
local SPELLS = require("generated.spells")
local Profile = require("character_profile")
local Wing = require("features.wing")

local M = { name = "garden" }

M.COLLECTION, M.KEY = "school", "garden"
M.AREA = "greenhouse"
M.PLOTS = 12
M.YIELD = 2
M.ABANDONED = 86400
-- Real minutes from watering to ripe.
M.GROW_MINUTES = { seed_glowcap = 10, seed_moonpetal = 15, seed_whisperroot = 20, seed_emberbloom = 25 }
M.HERB = { seed_glowcap = "glowcap", seed_moonpetal = "moonpetal", seed_whisperroot = "whisperroot", seed_emberbloom = "emberbloom" }

local function garden(api)
  local f = api.state.features
  if not f.garden then
    local g = Store.read(M.COLLECTION, M.KEY, nil) or {}
    f.garden = type(g.plots) == "table" and g.plots or {}
  end
  return f.garden
end

local function view(api)
  local out = {}
  for n, p in pairs(garden(api)) do
    out[tostring(n)] = { name = p.name, seed = p.seed, watered = p.watered_at ~= nil, ready = p.ready_at ~= nil and api.now >= p.ready_at, ready_at = p.ready_at or 0 }
  end
  return { plots = out }
end

local function save(api)
  Store.write(M.COLLECTION, M.KEY, nil, { plots = garden(api) })
  api.push("garden", view(api), nil)
end

function M.join(api, sid) api.push("garden", view(api), sid) end

-- Ripening is announced to everyone once a minute (the client also counts down).
function M.tick(api, now)
  local f = api.state.features
  if f.garden_tick and now - f.garden_tick < 60 then return end
  f.garden_tick = now
  local any = false
  for _, p in pairs(garden(api)) do
    if p.ready_at and not p.announced and now >= p.ready_at then
      p.announced = true
      any = true
      local s = api.sid_of_user(p.owner)
      if s then api.notice(s, "GARDEN_RIPE", { "ITEM_" .. M.HERB[p.seed]:upper() .. "_NAME" }, 6) end
    end
  end
  if any then save(api) end
end

local function plot_of(payload)
  local n = math.floor(tonumber(payload.plot) or 0)
  if n < 1 or n > M.PLOTS then return nil end
  return tostring(n)
end

M.requests = {}

-- {plot, seed}
M.requests.garden_plant = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local n = plot_of(payload)
  if not n then return nil, "bad_spot" end
  local g = garden(api)
  if g[n] then return nil, "plot_taken" end
  local seed = tostring(payload.seed or "")
  if not M.GROW_MINUTES[seed] then return nil, "not_a_seed" end
  if not api.take_item(sid, seed, 1) then return nil, "not_owned" end
  g[n] = { owner = api.uid(sid), name = api.name(sid), seed = seed, planted_at = api.now }
  save(api)
  return { plot = tonumber(n) }
end

-- {plot}: a watering can is by every bed.
M.requests.garden_water = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local n = plot_of(payload)
  local p = n and garden(api)[n]
  if not p then return nil, "nothing_planted" end
  if p.watered_at then return nil, "already_done" end
  p.watered_at = api.now
  p.ready_at = api.now + M.GROW_MINUTES[p.seed] * 60
  save(api)
  return { ready_at = p.ready_at }
end

-- {plot, spell}: a growth spell on a watered plant ripens it now.
M.requests.garden_spell = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local n = plot_of(payload)
  local p = n and garden(api)[n]
  if not p then return nil, "nothing_planted" end
  local spell = SPELLS.by_id[tostring(payload.spell or "")]
  local profile = api.profile(sid)
  if not spell or spell.effect_type ~= "growth" or not profile or not Profile.knows(profile, payload.spell) then return nil, "wrong_spell" end
  if not p.watered_at then return nil, "needs_water" end
  p.ready_at = math.min(p.ready_at or api.now, api.now)
  save(api)
  return { ready_at = p.ready_at }
end

-- {plot}
M.requests.garden_harvest = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local n = plot_of(payload)
  local g = garden(api)
  local p = n and g[n]
  if not p then return nil, "nothing_planted" end
  if not p.ready_at or api.now < p.ready_at then return nil, "not_ripe" end
  if p.owner ~= api.uid(sid) and api.now < p.ready_at + M.ABANDONED then return nil, "not_yours" end
  local herb = M.HERB[p.seed]
  local got = 0
  for _ = 1, M.YIELD do
    if not api.give_item(sid, herb) then got = got + 1 end
  end
  g[n] = nil
  save(api)
  Wing.contribute(api, 1)
  return { herb = herb, count = got }
end

return M
