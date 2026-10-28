-- Arrival: a character's very first time in the world starts at the railway station, with
-- the walk up to the castle ahead (the client places them; the train is the welcome). The
-- server remembers who has arrived so it happens once per character, and where each
-- character was when they left (their last accepted position and area), so a returning
-- player starts where they stopped. The client decides whether that place is still a
-- safe one to stand in (not a hidden room, not another house's rooms, not behind a
-- scheduled door); otherwise it uses the castle's start point.
--
-- Storage: school/arrival per user (server-only): { at, pos = {x, y, z}?, area?, left? }
-- Push "arrival": { first = bool, pos = {x, y, z}?, area? }

local Store = require("store")

local M = { name = "arrival" }

M.COLLECTION, M.KEY = "school", "arrival"

local function rounded(v) return math.floor(v * 100 + 0.5) / 100 end

function M.join(api, sid)
  local uid = api.uid(sid)
  local rec = Store.read(M.COLLECTION, M.KEY, uid)
  local data = { first = rec == nil }
  if rec and type(rec.pos) == "table" and #rec.pos == 3 then
    data.pos = rec.pos
    data.area = type(rec.area) == "string" and rec.area or ""
  end
  api.push("arrival", data, sid)
  if rec == nil then Store.write(M.COLLECTION, M.KEY, uid, { at = api.now }) end
end

function M.leave(api, sid)
  local uid = api.uid(sid)
  local pos = api.position(sid)
  if not uid or type(pos) ~= "table" or not tonumber(pos[1]) or not tonumber(pos[2]) or not tonumber(pos[3]) then return end
  local rec = Store.read(M.COLLECTION, M.KEY, uid) or { at = api.now }
  rec.pos = { rounded(pos[1]), rounded(pos[2]), rounded(pos[3]) }
  rec.area = api.area(sid)
  rec.left = api.now
  Store.write(M.COLLECTION, M.KEY, uid, rec)
end

return M
