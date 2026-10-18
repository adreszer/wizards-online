-- Player profiles: clicking a nameplate (or /profile name) shows another student's card:
-- house, year, role and titles (prefect, head of house, ladder champion), favourite spell
-- (the one with the most mastery), how many discoveries, club badges, parlour-game and
-- ladder records, their familiar. Only what other students could know anyway; no area.

local Clubs = require("features.clubs")
local Ladder = require("features.ladder")
local Games = require("features.games")
local Heads = require("features.heads")
local Friends = require("features.friends")

local M = { name = "profiles" }

M.requests = {}

-- {name}: the card of an online player.
M.requests.profile_card = function(api, sid, payload)
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  local p = api.profile(target)
  if not p then return nil, "no_player" end
  local uid = api.uid(target)
  local best, best_points = "", 0
  for id, points in pairs(p.mastery or {}) do
    if points > best_points or (points == best_points and id < best) then best, best_points = id, points end
  end
  local titles = {}
  if p.role ~= "student" then table.insert(titles, "ROLE_" .. p.role:upper() .. "_TITLE") end
  for h = 1, 4 do
    if Heads.is_head(api, target, h) then table.insert(titles, "TITLE_HEAD_OF_" .. h) end
  end
  local ladder_title = Ladder.title_of(api, api.name(target))
  if ladder_title ~= "" then table.insert(titles, ladder_title) end
  local f = api.state.features
  return { name = api.name(target), house = p.house, year = p.year or 1, role = p.role, titles = titles, favourite = best,
           discoveries = #(p.discoveries or {}), clubs = Clubs.of(api, uid), games = Games.stats(uid), rating = Ladder.rating_of(api, uid),
           familiar = f.familiars and f.familiars[target] or "", friend = Friends.are_friends(api.uid(sid), uid), self = target == sid }
end

return M
