-- Exploration and the Wayfinder's Chart. The server remembers every area each student
-- has walked into; the chart (an item, the stationer sells it) draws only those on the
-- map, marks discoveries, and, for house-mates who choose to share, shows which room
-- they are in. Each newly explored place adds to the Unfinished Wing's shared progress.
--
-- Storage: school/explored per user (owner-readable): { areas = { [area] = true }, share = bool }
-- Push "explored": { areas = [ids], share } on join; "explored_new": { area } after;
--      "chart_mates": { mates = [ { name, area } ] } every few seconds to sharing chart holders.

local Store = require("store")
local Wing = require("features.wing")

local M = { name = "explore" }

M.COLLECTION, M.KEY = "school", "explored"
M.ITEM = "wayfinder_chart"
M.MATES_EVERY = 3

local function cache(api)
  api.state.features.explored = api.state.features.explored or {}
  return api.state.features.explored
end

local function list(rec)
  local out = {}
  for a, _ in pairs(rec.areas) do table.insert(out, a) end
  table.sort(out)
  return out
end

function M.join(api, sid)
  local rec = Store.read(M.COLLECTION, M.KEY, api.uid(sid)) or {}
  rec.areas = type(rec.areas) == "table" and rec.areas or {}
  rec.share = rec.share == true
  cache(api)[sid] = rec
  api.push("explored", { areas = list(rec), share = rec.share }, sid)
end

function M.leave(api, sid) cache(api)[sid] = nil end

function M.area(api, sid, area)
  local rec = cache(api)[sid]
  if not rec or area == "" or rec.areas[area] then return end
  rec.areas[area] = true
  Store.write(M.COLLECTION, M.KEY, api.uid(sid), rec, true)
  api.push("explored_new", { area = area }, sid)
  Wing.contribute(api, 1)
end

-- Every few seconds: sharing house-mates' rooms to each sharing chart holder.
function M.tick(api, now)
  local f = api.state.features
  if f.mates_at and now - f.mates_at < M.MATES_EVERY then return end
  f.mates_at = now
  local by_house = {}
  for sid, rec in pairs(cache(api)) do
    local h = api.house(sid)
    if rec.share and h > 0 and api.online(sid) then
      by_house[h] = by_house[h] or {}
      table.insert(by_house[h], sid)
    end
  end
  for _, sids in pairs(by_house) do
    for _, sid in ipairs(sids) do
      if api.count_item(sid, M.ITEM) > 0 then
        local mates = {}
        for _, other in ipairs(sids) do
          if other ~= sid and api.area(other) ~= "" then table.insert(mates, { name = api.name(other), area = api.area(other) }) end
        end
        api.push("chart_mates", { mates = mates }, sid)
      end
    end
  end
end

M.requests = {}

-- {share = bool}: show my room to house-mates who carry the chart (and see theirs).
M.requests.chart_share = function(api, sid, payload)
  local rec = cache(api)[sid]
  if not rec then return nil, "no_player" end
  rec.share = payload.share == true
  Store.write(M.COLLECTION, M.KEY, api.uid(sid), rec, true)
  return { share = rec.share }
end

return M
