-- Character record shared by world.lua (admin RPC) and world_match.lua.
-- Storage: collection "character", key "profile", one object per user:
--   { v = 1, house = 0..4, role = "student"|"professor"|"admin",
--     spells = { known = {ids}, slots = {ids or ""}, equipped = id },
--     discoveries = {mystery discovery ids}, appearance = { body, skin, robe, set } }
-- Spell ids and the sorting questionnaire come from generated modules
-- (tools/export_server_content.gd), so the client's lists are the only source.

local nk = require("nakama")
local SPELLS = require("generated.spells")
local SORTING = require("generated.sorting")
local CHARACTERS = require("generated.characters")

local M = {}

M.COLLECTION, M.KEY = "character", "profile"
M.ROLES = { student = true, professor = true, admin = true }
M.MAX_HOUSE = 4
M.QUICK_SLOTS = 10
M.SPELLS = {}
for _, id in ipairs(SPELLS.ids) do
  M.SPELLS[id] = true
end

-- Sorting questionnaire: answer index (1-4) -> house, per question.
M.SORTING = SORTING.questions
M.COUNTS_KEY = "house_counts"

-- Scores per house for a list of answers, or nil when the answers are malformed.
function M.tally(answers)
  if type(answers) ~= "table" or #answers ~= #M.SORTING then
    return nil
  end
  local scores = { 0, 0, 0, 0 }
  for q, mapping in ipairs(M.SORTING) do
    local a = answers[q]
    if type(a) ~= "number" or a < 1 or a > #mapping or a ~= math.floor(a) then
      return nil
    end
    scores[mapping[a]] = scores[mapping[a]] + 1
  end
  return scores
end

-- System-owned counter of members per house, used to break ties evenly.
function M.load_counts()
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = M.COUNTS_KEY, user_id = nil } })
  if ok and objects and objects[1] and objects[1].value and type(objects[1].value.counts) == "table" then
    return objects[1].value.counts
  end
  return { 0, 0, 0, 0 }
end

function M.write_counts(counts)
  pcall(nk.storage_write, {
    { collection = M.COLLECTION, key = M.COUNTS_KEY, user_id = nil, value = { counts = counts }, permission_read = 0, permission_write = 0 },
  })
end

-- The house with the highest score; ties go to the emptiest of the tied houses.
function M.pick_house(scores, counts)
  local best = 1
  for h = 2, M.MAX_HOUSE do
    if scores[h] > scores[best] or (scores[h] == scores[best] and (counts[h] or 0) < (counts[best] or 0)) then
      best = h
    end
  end
  return best
end

function M.is_staff(role)
  return role == "professor" or role == "admin"
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

function M.sanitize_spells(raw)
  local known, seen = {}, {}
  if type(raw) == "table" and type(raw.known) == "table" then
    for _, id in ipairs(raw.known) do
      if type(id) == "string" and M.SPELLS[id] and not seen[id] then
        seen[id] = true
        table.insert(known, id)
      end
    end
  end
  local slots, slotted = {}, {}
  if type(raw) == "table" and type(raw.slots) == "table" then
    for i = 1, M.QUICK_SLOTS do
      local id = raw.slots[i]
      if type(id) == "string" and seen[id] and not slotted[id] then
        slotted[id] = true
        slots[i] = id
      else
        slots[i] = ""
      end
    end
  else
    for i = 1, M.QUICK_SLOTS do slots[i] = "" end
  end
  -- Known but unslotted spells take the first free slot (same rule as SpellCaster.load_state).
  for _, id in ipairs(known) do
    if not slotted[id] then
      for i = 1, M.QUICK_SLOTS do
        if slots[i] == "" then
          slots[i] = id
          slotted[id] = true
          break
        end
      end
    end
  end
  local equipped = ""
  if type(raw) == "table" and type(raw.equipped) == "string" and seen[raw.equipped] then
    equipped = raw.equipped
  elseif #known > 0 then
    equipped = known[1]
  end
  return { known = known, slots = slots, equipped = equipped }
end

M.MAX_DISCOVERIES = 256

function M.sanitize_discoveries(raw)
  local out, seen = {}, {}
  if type(raw) == "table" then
    for _, id in ipairs(raw) do
      if type(id) == "string" and #id > 0 and #id <= 64 and not seen[id] and #out < M.MAX_DISCOVERIES then
        seen[id] = true
        table.insert(out, id)
      end
    end
  end
  return out
end

-- Records a discovery (a solved mystery's reward). Returns true when new.
function M.discover(profile, id)
  if contains(profile.discoveries, id) then
    return false
  end
  table.insert(profile.discoveries, id)
  return true
end

-- The character's look: body (a character id), skin tone and robe colour (indices into
-- CharacterLook's lists), and whether the player chose it (the creator opens until then).
function M.sanitize_appearance(raw)
  local out = { body = CHARACTERS.default, skin = 0, robe = 0, set = false }
  if type(raw) ~= "table" then return out end
  for _, id in ipairs(CHARACTERS.ids) do
    if raw.body == id then out.body = id end
  end
  local skin, robe = math.floor(tonumber(raw.skin) or 0), math.floor(tonumber(raw.robe) or 0)
  if skin >= 0 and skin < (CHARACTERS.skin_tones or 1) then out.skin = skin end
  if robe >= 0 and robe < (CHARACTERS.robes or 1) then out.robe = robe end
  out.set = raw.set == true
  return out
end

function M.sanitize(raw)
  local profile = { v = 1, house = 0, role = "student", spells = nil, discoveries = {} }
  if type(raw) == "table" then
    local house = math.floor(tonumber(raw.house) or 0)
    if house >= 0 and house <= M.MAX_HOUSE then
      profile.house = house
    end
    if type(raw.role) == "string" and M.ROLES[raw.role] then
      profile.role = raw.role
    end
    profile.spells = M.sanitize_spells(raw.spells)
    profile.discoveries = M.sanitize_discoveries(raw.discoveries)
    profile.appearance = M.sanitize_appearance(raw.appearance)
  else
    profile.spells = M.sanitize_spells(nil)
    profile.appearance = M.sanitize_appearance(nil)
  end
  return profile
end

function M.write(uid, profile)
  local ok, err = pcall(nk.storage_write, {
    { collection = M.COLLECTION, key = M.KEY, user_id = uid, value = profile, permission_read = 1, permission_write = 0 },
  })
  if not ok then
    nk.logger_warn(string.format("profile write failed for %s: %s", uid, tostring(err)))
  end
  return ok
end

-- Reads the user's profile, creating a fresh student record on first join.
function M.load(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = M.KEY, user_id = uid } })
  if ok and objects and objects[1] and objects[1].value then
    return M.sanitize(objects[1].value)
  end
  local profile = M.sanitize(nil)
  M.write(uid, profile)
  return profile
end

-- Adds a spell to the spellbook (first free slot, equipped). Returns true when new.
function M.grant_spell(profile, id)
  if not M.SPELLS[id] or contains(profile.spells.known, id) then
    return false
  end
  table.insert(profile.spells.known, id)
  for i = 1, M.QUICK_SLOTS do
    if profile.spells.slots[i] == "" then
      profile.spells.slots[i] = id
      break
    end
  end
  profile.spells.equipped = id
  return true
end

function M.knows(profile, id)
  return contains(profile.spells.known, id)
end

-- Comma-separated user ids from the ADMIN_USER_IDS runtime env variable.
function M.env_admins(env)
  local out = {}
  local raw = env and env["ADMIN_USER_IDS"]
  if type(raw) == "string" then
    for id in raw:gmatch("[^,%s]+") do
      out[id] = true
    end
  end
  return out
end

return M
