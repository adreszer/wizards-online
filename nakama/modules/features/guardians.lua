-- Shared enemies: the dungeon guardians' health, deaths and respawns belong to the
-- server, so everyone fighting one fights the same guardian. A student's spell that
-- hits a guardian is reported by their client (guardian_hit); the server checks they
-- stand in its area, know the spell and are not hitting faster than spells allow, and
-- takes the damage for that spell's effect (nakama/content/guardians.json). At zero it
-- falls for everyone; everyone who hurt it earns house points and a few coins, and the
-- Unfinished Wing's progress moves. It wakes again after respawn_seconds. Night-only
-- guardians stand only during curfew. Each client still animates the chase itself.
--
-- Memory only (a restart wakes every guardian): state.features.guardians[id] = { hp, dead_until, hurt = { sid = true } }
-- Push "guardians": { [id] = { hp, max, dead, active } } to everyone.

local Store = require("store")
local SPELLS = require("generated.spells")
local Profile = require("character_profile")
local Wing = require("features.wing")

local M = { name = "guardians" }

M.HIT_GAP = 0.45

local content
local function defs()
  if not content then
    content = Store.content("guardians.json") or {}
    content.guardians = type(content.guardians) == "table" and content.guardians or {}
    content.damage = type(content.damage) == "table" and content.damage or {}
    content.reward = type(content.reward) == "table" and content.reward or {}
    content.respawn_seconds = tonumber(content.respawn_seconds) or 120
  end
  return content
end

local function night(api)
  local h = api.school_hours()
  return h >= 22 or h < 6
end

local function all(api)
  local f = api.state.features
  if not f.guardians then
    f.guardians = {}
    for id, g in pairs(defs().guardians) do
      f.guardians[id] = { hp = tonumber(g.hp) or 100, dead_until = 0, hurt = {} }
    end
  end
  return f.guardians
end

local function view(api)
  local out = {}
  for id, s in pairs(all(api)) do
    local g = defs().guardians[id]
    out[id] = { hp = s.hp, max = tonumber(g.hp) or 100, dead = s.dead_until > api.now, active = not g.night_only or night(api) }
  end
  return out
end

local function send(api) api.push("guardians", view(api), nil) end

function M.join(api, sid) api.push("guardians", view(api), sid) end

function M.tick(api, now)
  local f = api.state.features
  local changed = false
  for id, s in pairs(all(api)) do
    if s.dead_until > 0 and now >= s.dead_until then
      s.dead_until, s.hp, s.hurt = 0, tonumber(defs().guardians[id].hp) or 100, {}
      changed = true
    end
  end
  local n = night(api)
  if f.guardians_night ~= n then
    f.guardians_night = n
    changed = true
  end
  if changed then send(api) end
end

M.requests = {}

-- {id, spell}: the caster's spell hit guardian `id`.
M.requests.guardian_hit = function(api, sid, payload)
  local id = tostring(payload.id or "")
  local g = defs().guardians[id]
  if not g then return nil, "unknown_guardian" end
  local s = all(api)[id]
  if s.dead_until > api.now then return nil, "already_down" end
  if g.night_only and not night(api) then return nil, "not_here" end
  if api.area(sid) ~= g.area then return nil, "out_of_reach" end
  local spell = SPELLS.by_id[tostring(payload.spell or "")]
  if not spell then return nil, "unknown_spell" end
  local profile = api.profile(sid)
  if not profile or not Profile.knows(profile, payload.spell) then return nil, "spell_not_known" end
  local f = api.state.features
  f.guardian_hit_at = f.guardian_hit_at or {}
  if f.guardian_hit_at[sid] and api.now - f.guardian_hit_at[sid] < M.HIT_GAP then return nil, "too_fast" end
  f.guardian_hit_at[sid] = api.now
  local damage = tonumber(defs().damage[spell.effect_type]) or tonumber(defs().default_damage) or 10
  s.hp = math.max(0, s.hp - damage)
  s.hurt[sid] = true
  if s.hp == 0 then
    s.dead_until = api.now + defs().respawn_seconds
    local r = defs().reward
    for hsid, _ in pairs(s.hurt) do
      if api.online(hsid) then
        local h = api.house(hsid)
        if h > 0 and (tonumber(r.house_points) or 0) > 0 then api.award(h, r.house_points, "guardian defeated: " .. api.name(hsid), "guardian") end
        if (tonumber(r.coins) or 0) > 0 then api.pay(hsid, r.coins, "event", "guardian") end
        api.notice(hsid, "GUARDIAN_DEFEATED_TOGETHER", {}, 5)
      end
    end
    Wing.contribute(api, 3)
  end
  send(api)
  return { hp = s.hp, dead = s.hp == 0 }
end

return M
