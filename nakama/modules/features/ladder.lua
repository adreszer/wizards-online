-- The duel ladder: every finished duel between two students (duelling club rooms only,
-- duel.lua) moves both ratings (Elo, start 1000, K 24); a forfeit counts as a loss.
-- Each calendar term is a season: when it changes, the three best get a cosmetic title
-- for the next season and a small trophy (decor), and ratings start again.
--
-- Storage: social/ladder (system): { season, players = { [uid] = { name, rating, wins, losses } }, champions = { {name, place} } }
-- Push "ladder": { season, top = [ {name, rating, wins, losses} ], champions } on join and after each duel.

local Store = require("store")
local Wing = require("features.wing")

local M = { name = "ladder" }

M.COLLECTION, M.KEY = "social", "ladder"
M.START, M.K = 1000, 24
M.TOP = 10

local function ladder(api)
  local f = api.state.features
  if not f.ladder then
    local l = Store.read(M.COLLECTION, M.KEY, nil) or {}
    l.players = type(l.players) == "table" and l.players or {}
    l.champions = type(l.champions) == "table" and l.champions or {}
    l.season = l.season or ""
    f.ladder = l
  end
  return f.ladder
end

-- New ratings after a game: winner, loser.
function M.elo(rw, rl)
  local expected = 1 / (1 + 10 ^ ((rl - rw) / 400))
  local delta = math.floor(M.K * (1 - expected) + 0.5)
  return rw + delta, rl - delta
end

local function top(l)
  local list = {}
  for _, p in pairs(l.players) do table.insert(list, p) end
  table.sort(list, function(a, b)
    if a.rating ~= b.rating then return a.rating > b.rating end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(M.TOP, #list) do out[i] = list[i] end
  return out
end

local function view(api) local l = ladder(api) return { season = l.season, top = top(l), champions = l.champions } end

local function entry(l, uid, name)
  local p = l.players[uid]
  if not p then
    p = { name = name, rating = M.START, wins = 0, losses = 0 }
    l.players[uid] = p
  end
  p.name = name
  return p
end

function M.join(api, sid) api.push("ladder", view(api), sid) end

-- The season is the calendar term (timetable.lua); a new term crowns the old one's best.
local function check_season(api)
  local l = ladder(api)
  local term = require("timetable").term_id(api.timetable(), api.now)
  if term == "" or term == l.season then return end
  if l.season ~= "" then
    local best = top(l)
    l.champions = {}
    for i = 1, math.min(3, #best) do
      table.insert(l.champions, { name = best[i].name, place = i, season = l.season })
      for uid, p in pairs(l.players) do
        if p == best[i] then
          local s = api.sid_of_user(uid)
          if s then api.give_item(s, "trophy_small") end
        end
      end
    end
    l.players = {}
  end
  l.season = term
  Store.write(M.COLLECTION, M.KEY, nil, l)
end

function M.tick(api, now)
  local finished = api.state.finished_duels or {}
  if #finished == 0 then
    local f = api.state.features
    if not f.ladder_season_at or now - f.ladder_season_at > 60 then
      f.ladder_season_at = now
      check_season(api)
    end
    return
  end
  api.state.finished_duels = {}
  local l = ladder(api)
  for _, duel in ipairs(finished) do
    if duel.winner and not duel.expired then
      local loser = duel.winner == duel.a and duel.b or duel.a
      local wu, lu = api.uid(duel.winner), api.uid(loser)
      if wu and lu and not api.is_staff(duel.winner) and not api.is_staff(loser) then
        local w, ls = entry(l, wu, api.name(duel.winner)), entry(l, lu, api.name(loser))
        w.rating, ls.rating = M.elo(w.rating, ls.rating)
        w.wins, ls.losses = w.wins + 1, ls.losses + 1
        Wing.contribute(api, 2)
      end
    end
  end
  Store.write(M.COLLECTION, M.KEY, nil, l)
  api.push("ladder", view(api), nil)
end

-- A champion's title for profile cards ("" when none).
function M.title_of(api, name)
  for _, c in ipairs(ladder(api).champions) do
    if c.name == name then return "LADDER_TITLE_" .. c.place end
  end
  return ""
end

function M.rating_of(api, uid)
  local p = ladder(api).players[uid]
  return p and p.rating or nil
end

M.requests = {}
M.requests.ladder_view = function(api, sid, payload) return view(api) end

return M
