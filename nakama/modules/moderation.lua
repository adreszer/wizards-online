-- Moderation: a word filter for everything players write to each other (chat, DMs,
-- lecture and board text), reports, mutes, kicks, bans and personal block lists.
--
-- Storage:
--   moderation/<user id>   system-owned: { muted_until, banned, reason, by }
--   reports/<uuid>         system-owned: { from, from_name, about, about_name, reason, at }
--   blocks/list            per user, owner-readable: { users = { user id = name } }

local nk = require("nakama")

local M = {}

M.FILTER_PATH = "../content/word_filter.json"
M.COLLECTION, M.REPORTS, M.BLOCKS = "moderation", "reports", "blocks"
M.FOLD = { ["ą"] = "a", ["ć"] = "c", ["ę"] = "e", ["ł"] = "l", ["ń"] = "n", ["ó"] = "o", ["ś"] = "s", ["ź"] = "z", ["ż"] = "z",
           ["Ą"] = "a", ["Ć"] = "c", ["Ę"] = "e", ["Ł"] = "l", ["Ń"] = "n", ["Ó"] = "o", ["Ś"] = "s", ["Ź"] = "z", ["Ż"] = "z" }

function M.load_filter()
  local ok, raw = pcall(nk.file_read, M.FILTER_PATH)
  if not ok then return {} end
  local ok2, data = pcall(nk.json_decode, raw)
  return (ok2 and type(data) == "table" and type(data.stems) == "table") and data.stems or {}
end

-- A word folded to plain lower-case ASCII letters (Polish diacritics folded).
function M.fold(word)
  local out = word
  for k, v in pairs(M.FOLD) do out = out:gsub(k, v) end
  return out:lower()
end

-- `text` with every word starting with a filtered stem replaced by asterisks.
function M.filter(text, stems)
  if #stems == 0 then return text end
  return (text:gsub("[^%s%p]+", function(word)
    local folded = M.fold(word)
    for _, stem in ipairs(stems) do
      if folded:sub(1, #stem) == stem then
        return string.rep("*", math.max(3, utf8 and utf8.len(word) or #word))
      end
    end
    return word
  end))
end

function M.load(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = uid, user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return {}
end

function M.save(uid, rec)
  pcall(nk.storage_write, { { collection = M.COLLECTION, key = uid, user_id = nil, value = rec, permission_read = 0, permission_write = 0 } })
end

function M.is_muted(rec, now)
  return (rec.muted_until or 0) > now
end

function M.report(entry)
  entry.at = nk.time() / 1000
  pcall(nk.storage_write, { { collection = M.REPORTS, key = nk.uuid_v4(), user_id = nil, value = entry, permission_read = 0, permission_write = 0 } })
end

function M.list_reports(limit)
  local out = {}
  local ok, objects = pcall(nk.storage_list, nil, M.REPORTS, math.min(100, limit), "")
  if ok then
    for _, o in ipairs(objects or {}) do
      if type(o.value) == "table" then table.insert(out, o.value) end
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function M.load_blocks(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = M.BLOCKS, key = "list", user_id = uid } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" and type(objects[1].value.users) == "table" then
    return objects[1].value.users
  end
  return {}
end

function M.save_blocks(uid, users)
  pcall(nk.storage_write, { { collection = M.BLOCKS, key = "list", user_id = uid, value = { users = users }, permission_read = 1, permission_write = 0 } })
end

return M
