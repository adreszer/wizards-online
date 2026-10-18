-- Arrival: a character's very first time in the world starts at the railway station, with
-- the walk up to the castle ahead (the client places them; the train is the welcome). The
-- server remembers who has arrived so it happens once per character.
--
-- Storage: school/arrival per user (server-only): { at }
-- Push "arrival": { first = bool }

local Store = require("store")

local M = { name = "arrival" }

M.COLLECTION, M.KEY = "school", "arrival"

function M.join(api, sid)
  local uid = api.uid(sid)
  local rec = Store.read(M.COLLECTION, M.KEY, uid)
  api.push("arrival", { first = rec == nil }, sid)
  if rec == nil then Store.write(M.COLLECTION, M.KEY, uid, { at = api.now }) end
end

return M
