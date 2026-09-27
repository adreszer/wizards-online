-- Character record shared by world.lua (admin RPC) and world_match.lua.
-- Storage: collection "character", key "profile", one object per user:
--   { v = 1, house = 0..4, role = "student"|"professor"|"admin",
--     spells = { known = {ids}, slots = {ids or ""}, equipped = id } }
-- The spell id list mirrors SpellRegistry.SPELL_IDS (res://gameplay/spells/
-- spell_registry.gd); keep the two in sync.

local nk = require("nakama")

local M = {}

M.COLLECTION, M.KEY = "character", "profile"
M.ROLES = { student = true, professor = true, admin = true }
M.MAX_HOUSE = 4
M.QUICK_SLOTS = 10
M.SPELLS = {}
for _, id in ipairs({ "arcane_pulse", "uplift", "galewind", "emberkindle", "wellspring", "frostbind",
                      "glowmote", "duskveil", "unbolt", "mendweave", "quicksprout" }) do
  M.SPELLS[id] = true
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
  -- Known but unslotted spells take the first free slot (mirrors SpellCaster.load_state).
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

function M.sanitize(raw)
  local profile = { v = 1, house = 0, role = "student", spells = nil }
  if type(raw) == "table" then
    local house = math.floor(tonumber(raw.house) or 0)
    if house >= 0 and house <= M.MAX_HOUSE then
      profile.house = house
    end
    if type(raw.role) == "string" and M.ROLES[raw.role] then
      profile.role = raw.role
    end
    profile.spells = M.sanitize_spells(raw.spells)
  else
    profile.spells = M.sanitize_spells(nil)
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
