-- Chat routing, decided on the server: proximity chat (say, whisper, shout) reaches
-- only players near the speaker, direct messages reach one player (or wait in their
-- mailbox while they are away). Positions come from the players' own movement
-- snapshots (OP_STATE), areas from their area reports, so the server never relays a
-- line to someone who could not have heard it.
--
-- Storage:
--   names/<lower-case display name>   system-owned: { uid, name } (who a DM goes to)
--   mail/<uuid>                       per recipient, owner-readable: { from, from_name, text, at }

local nk = require("nakama")
local School = require("school")

local M = {}

-- Hearing range in metres per mode. Say and whisper also stay inside the speaker's
-- area (a classroom conversation stays in the classroom); a shout carries through
-- doors and walls.
M.RANGES = { whisper = 4, say = 18, shout = 45 }
M.MODES = { whisper = true, say = true, shout = true }
M.MAX_TEXT_BYTES = 400   -- 200 characters of Polish can take two bytes each
M.NAME_COLLECTION, M.MAIL_COLLECTION = "names", "mail"
M.MAX_MAIL = 50          -- a mailbox holds at most this many waiting messages

-- The position in an OP_STATE payload ("p":[x,y,z]) without decoding the rest.
function M.position_of(data)
  if type(data) ~= "string" then return nil end
  local x, y, z = data:match('"p":%[%s*(%-?[%d%.eE+-]+)%s*,%s*(%-?[%d%.eE+-]+)%s*,%s*(%-?[%d%.eE+-]+)%s*%]')
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not x or not y or not z then return nil end
  return { x, y, z }
end

-- Whether `listener` hears `speaker` in `mode`; each is { pos = {x,y,z} or nil, area = id or "" }.
-- Without both positions only a shared area counts.
function M.hears(mode, speaker, listener)
  local range = M.RANGES[mode]
  if not range then return false end
  local same_area = speaker.area == listener.area
  if mode ~= "shout" and speaker.area ~= "" and not same_area then
    return false
  end
  local a, b = speaker.pos, listener.pos
  if not a or not b then
    return same_area
  end
  local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return dx * dx + dy * dy + dz * dz <= range * range
end

function M.clean(text)
  return School.clean_text(text, M.MAX_TEXT_BYTES)
end

local function name_key(name)
  return string.lower(name or "")
end

-- Remembers who goes by `name` (on every join), so a DM can find them offline.
function M.remember_name(uid, name)
  if type(name) ~= "string" or name == "" then return end
  pcall(nk.storage_write, {
    { collection = M.NAME_COLLECTION, key = name_key(name), user_id = nil, value = { uid = uid, name = name }, permission_read = 0, permission_write = 0 },
  })
end

-- The user id that last joined under `name`, or nil.
function M.uid_for_name(name)
  local ok, objects = pcall(nk.storage_read, { { collection = M.NAME_COLLECTION, key = name_key(name), user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then
    return objects[1].value.uid, objects[1].value.name
  end
  return nil
end

-- Leaves a DM in `uid`'s mailbox. Returns nil or a reason ("mailbox_full").
function M.post_mail(uid, mail)
  local ok, objects = pcall(nk.storage_list, uid, M.MAIL_COLLECTION, M.MAX_MAIL, "")
  if ok and objects and #objects >= M.MAX_MAIL then
    return "mailbox_full"
  end
  local written = pcall(nk.storage_write, {
    { collection = M.MAIL_COLLECTION, key = nk.uuid_v4(), user_id = uid, value = mail, permission_read = 1, permission_write = 0 },
  })
  if not written then return "storage" end
  return nil
end

-- Takes every waiting message out of `uid`'s mailbox, oldest first.
function M.take_mail(uid)
  local ok, objects = pcall(nk.storage_list, uid, M.MAIL_COLLECTION, M.MAX_MAIL, "")
  local out, deletes = {}, {}
  if ok and objects then
    for _, o in ipairs(objects) do
      if type(o.value) == "table" then table.insert(out, o.value) end
      table.insert(deletes, { collection = M.MAIL_COLLECTION, key = o.key, user_id = uid })
    end
  end
  if #deletes > 0 then pcall(nk.storage_delete, deletes) end
  table.sort(out, function(a, b) return (a.at or 0) < (b.at or 0) end)
  return out
end

return M
