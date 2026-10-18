-- Lantern Chase (Pościg z Latarnią, placeholder name): the school's own flying sport, on
-- the pitch. Rings and lanterns are placed by x and z (the client puts them over the
-- terrain); scoring needs the carrier on a broom. Two teams of up to four; each team has a lantern at its end of the pitch
-- and scores by carrying its lit lantern through the ring at the other end. Defenders
-- snuff the carrier's lantern with a wind or water spell (Galewind, Wellspring): it drops
-- where it was, unlit; a team-mate relights it with fire (Emberkindle) and picks it up.
-- A match lasts MATCH_SECONDS; the higher score wins. When each team is a single house,
-- the winners' house earns house points; everyone who played earns a few coins.
--
-- Every claim is checked: the lantern is taken only near it, scored only by its carrier
-- near the far ring (positions from the riders' own state reports), snuffed only by a
-- rival who knows a wind or water spell, relit only by a team-mate with a fire spell.
--
-- Memory only: state.features.chase = { state = "lobby" | "playing", teams, scores, lanterns, ends_at }
-- Push "lantern_chase": the match as everyone on the pitch sees it.

local SPELLS = require("generated.spells")
local Profile = require("character_profile")
local Wing = require("features.wing")

local M = { name = "lantern_chase" }

M.AREA = "pitch"
M.MAX_TEAM = 4
M.MATCH_SECONDS = 300
M.TAKE_REACH = 3.5
M.RING_REACH = 6.0
M.RING_HEIGHT = 7.0
M.SNUFF_GAP = 1.0
M.HOUSE_POINTS, M.COINS = 10, 5
M.AWAY_SECONDS = 10
M.SNUFF_EFFECTS = { wind = true, water = true }
M.FIRE_EFFECTS = { fire = true }

local function other(team) return team == "a" and "b" or "a" end

-- Distance over the ground (the server does not know the pitch's terrain height, so
-- only x and z count; rings need the carrier to be riding a broom instead).
local function dist(p, q)
  if not p or not q then return math.huge end
  local dx, dz = p[1] - q[1], p[3] - q[3]
  return math.sqrt(dx * dx + dz * dz)
end

-- The pitch's long axis and its two ends: rings (team a scores at "b"'s end) and lantern homes.
function M.layout(def)
  local c, s = def.c, def.s
  local floor_y = c[2] - s[2] / 2
  local ax = s[1] >= s[3]
  local half = (ax and s[1] or s[3]) / 2
  local function at(f, h)
    if ax then return { c[1] + f * half, floor_y + h, c[3] } end
    return { c[1], floor_y + h, c[3] + f * half }
  end
  return { rings = { a = at(0.8, M.RING_HEIGHT), b = at(-0.8, M.RING_HEIGHT) },
           homes = { a = at(-0.6, 1.2), b = at(0.6, 1.2) } }
end

local function chase(api)
  local f = api.state.features
  if not f.chase then
    local def = api.AREAS[M.AREA]
    f.chase = { state = "lobby", teams = { a = {}, b = {} }, scores = { a = 0, b = 0 }, lanterns = {}, ends_at = 0,
                layout = def and def.c and M.layout(def) or nil }
    for _, t in ipairs({ "a", "b" }) do
      f.chase.lanterns[t] = { carrier = nil, lit = true, pos = f.chase.layout and f.chase.layout.homes[t] or { 0, 0, 0 } }
    end
  end
  return f.chase
end

local function team_of(c, sid)
  for _, t in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[t]) do
      if s == sid then return t end
    end
  end
  return nil
end

local function view(api, c)
  local teams, lanterns = { a = {}, b = {} }, {}
  for _, t in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[t]) do table.insert(teams[t], api.name(s)) end
    local l = c.lanterns[t]
    lanterns[t] = { carrier = l.carrier and api.name(l.carrier) or "", lit = l.lit, pos = l.pos }
  end
  return { state = c.state, teams = teams, scores = c.scores, lanterns = lanterns, ends_at = c.ends_at,
           rings = c.layout and c.layout.rings or nil, left = c.state == "playing" and math.max(0, math.floor(c.ends_at - api.now)) or 0 }
end

local function send(api, c)
  local sids = {}
  local seen = {}
  for _, pl in ipairs(api.players_in(M.AREA)) do
    table.insert(sids, pl.sid)
    seen[pl.sid] = true
  end
  for _, t in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[t]) do
      if not seen[s] then table.insert(sids, s) end
    end
  end
  if #sids > 0 then api.push("lantern_chase", view(api, c), sids) end
end

local function reset_lantern(c, t)
  c.lanterns[t] = { carrier = nil, lit = true, pos = c.layout and c.layout.homes[t] or { 0, 0, 0 } }
end

local function drop(api, c, sid)
  for _, t in ipairs({ "a", "b" }) do
    local l = c.lanterns[t]
    if l.carrier == sid then
      l.carrier = nil
      l.pos = api.position(sid) or l.pos
    end
  end
end

local function remove(api, c, sid)
  drop(api, c, sid)
  for _, t in ipairs({ "a", "b" }) do
    for i, s in ipairs(c.teams[t]) do
      if s == sid then table.remove(c.teams[t], i) break end
    end
  end
end

-- The single house of a team, or 0 when mixed or empty.
local function house_of_team(api, list)
  local h
  for _, s in ipairs(list) do
    local sh = api.house(s)
    if h == nil then h = sh elseif h ~= sh then return 0 end
  end
  return h or 0
end

local function finish(api, c)
  local winner = c.scores.a > c.scores.b and "a" or (c.scores.b > c.scores.a and "b" or nil)
  for _, t in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[t]) do
      api.pay(s, M.COINS, "event", "lantern chase")
      api.notice(s, winner == nil and "CHASE_DRAW" or (winner == t and "CHASE_WON" or "CHASE_LOST"), { c.scores.a, c.scores.b }, 8)
    end
  end
  if winner then
    local h = house_of_team(api, c.teams[winner])
    local h_other = house_of_team(api, c.teams[other(winner)])
    if h > 0 and h_other > 0 and h ~= h_other then
      api.award(h, M.HOUSE_POINTS, "lantern chase", "match")
      api.rumour("RUMOUR_CHASE", h)
    end
  end
  Wing.contribute(api, 5)
  c.state = "lobby"
  c.scores = { a = 0, b = 0 }
  reset_lantern(c, "a")
  reset_lantern(c, "b")
  send(api, c)
end

-- Walking (or flying) onto the pitch shows the match; players who stay off it longer
-- than AWAY_SECONDS leave their team (tick), so a wide turn over the stands does not.
function M.area(api, sid, area, previous)
  if area == M.AREA then send(api, chase(api)) end
end

function M.leave(api, sid)
  local c = chase(api)
  if team_of(c, sid) then
    remove(api, c, sid)
    send(api, c)
  end
end

function M.tick(api, now)
  local c = chase(api)
  c.away = c.away or {}
  local changed = false
  for _, t in ipairs({ "a", "b" }) do
    for i = #c.teams[t], 1, -1 do
      local s = c.teams[t][i]
      if api.area(s) == M.AREA then
        c.away[s] = nil
      else
        c.away[s] = c.away[s] or now
        if now - c.away[s] > M.AWAY_SECONDS then
          c.away[s] = nil
          remove(api, c, s)
          changed = true
        end
      end
    end
  end
  if c.state ~= "playing" then
    if changed then send(api, c) end
    return
  end
  for _, t in ipairs({ "a", "b" }) do
    local l = c.lanterns[t]
    if l.carrier then l.pos = api.position(l.carrier) or l.pos end
  end
  if now >= c.ends_at or #c.teams.a == 0 or #c.teams.b == 0 then
    finish(api, c)
  else
    send(api, c)
  end
end

M.requests = {}

-- {team = "a" | "b"}
M.requests.chase_join = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local c = chase(api)
  if not c.layout then return nil, "not_here" end
  local team = payload.team == "b" and "b" or "a"
  remove(api, c, sid)
  if #c.teams[team] >= M.MAX_TEAM then return nil, "team_full" end
  table.insert(c.teams[team], sid)
  send(api, c)
  return { team = team }
end

M.requests.chase_leave = function(api, sid, payload)
  local c = chase(api)
  if not team_of(c, sid) then return nil, "not_playing" end
  remove(api, c, sid)
  send(api, c)
  return {}
end

M.requests.chase_start = function(api, sid, payload)
  local c = chase(api)
  if not team_of(c, sid) then return nil, "not_playing" end
  if c.state == "playing" then return nil, "already_playing" end
  if #c.teams.a == 0 or #c.teams.b == 0 then return nil, "need_two_teams" end
  c.state, c.scores, c.ends_at = "playing", { a = 0, b = 0 }, api.now + M.MATCH_SECONDS
  reset_lantern(c, "a")
  reset_lantern(c, "b")
  for _, t in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[t]) do api.notice(s, "CHASE_STARTS", {}, 5) end
  end
  send(api, c)
  return { ends_at = c.ends_at }
end

-- A player takes their team's lit lantern from where it lies.
M.requests.chase_take = function(api, sid, payload)
  local c = chase(api)
  local t = team_of(c, sid)
  if not t or c.state ~= "playing" then return nil, "not_playing" end
  local l = c.lanterns[t]
  if l.carrier then return nil, "already_carried" end
  if not l.lit then return nil, "lantern_out" end
  if dist(api.position(sid), l.pos) > M.TAKE_REACH then return nil, "too_far" end
  l.carrier = sid
  send(api, c)
  return {}
end

-- The carrier reports passing the far ring.
M.requests.chase_ring = function(api, sid, payload)
  local c = chase(api)
  local t = team_of(c, sid)
  if not t or c.state ~= "playing" then return nil, "not_playing" end
  local l = c.lanterns[t]
  if l.carrier ~= sid or not l.lit then return nil, "not_carrying" end
  local ring = c.layout.rings[t]
  if dist(api.position(sid), ring) > M.RING_REACH then return nil, "too_far" end
  if not api.riding(sid) then return nil, "not_flying" end
  c.scores[t] = c.scores[t] + 1
  reset_lantern(c, t)
  for _, tt in ipairs({ "a", "b" }) do
    for _, s in ipairs(c.teams[tt]) do api.notice(s, "CHASE_SCORED", { api.name(sid), c.scores.a, c.scores.b }, 4) end
  end
  send(api, c)
  return { scores = c.scores }
end

-- {sid, spell}: a rival's spell hit the carrier.
M.requests.chase_snuff = function(api, sid, payload)
  local c = chase(api)
  local t = team_of(c, sid)
  if not t or c.state ~= "playing" then return nil, "not_playing" end
  local spell = SPELLS.by_id[tostring(payload.spell or "")]
  local profile = api.profile(sid)
  if not spell or not M.SNUFF_EFFECTS[spell.effect_type] or not profile or not Profile.knows(profile, payload.spell) then return nil, "wrong_spell" end
  local f = api.state.features
  f.snuff_at = f.snuff_at or {}
  if f.snuff_at[sid] and api.now - f.snuff_at[sid] < M.SNUFF_GAP then return nil, "too_fast" end
  f.snuff_at[sid] = api.now
  local l = c.lanterns[other(t)]
  if not l.carrier or l.carrier ~= payload.sid then return nil, "not_the_carrier" end
  l.pos = api.position(l.carrier) or l.pos
  l.carrier, l.lit = nil, false
  send(api, c)
  return {}
end

-- {spell}: a team-mate relights their dropped lantern with fire.
M.requests.chase_relight = function(api, sid, payload)
  local c = chase(api)
  local t = team_of(c, sid)
  if not t or c.state ~= "playing" then return nil, "not_playing" end
  local spell = SPELLS.by_id[tostring(payload.spell or "")]
  local profile = api.profile(sid)
  if not spell or not M.FIRE_EFFECTS[spell.effect_type] or not profile or not Profile.knows(profile, payload.spell) then return nil, "wrong_spell" end
  local l = c.lanterns[t]
  if l.lit then return nil, "already_lit" end
  if dist(api.position(sid), l.pos) > M.TAKE_REACH + 1 then return nil, "too_far" end
  l.lit = true
  send(api, c)
  return {}
end

return M
