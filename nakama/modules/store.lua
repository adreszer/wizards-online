-- Small storage helpers for feature modules: one JSON value per (collection, key,
-- user). A nil user is the system owner. Values that are not tables read as nil.

local nk = require("nakama")

local M = {}

function M.read(collection, key, uid)
  local ok, objects = pcall(nk.storage_read, { { collection = collection, key = key, user_id = uid } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return nil
end

-- Writes `value`; `public` lets the owner read it from the client (permission_read 1).
-- Returns true when stored.
function M.write(collection, key, uid, value, public)
  local ok, err = pcall(nk.storage_write, {
    { collection = collection, key = key, user_id = uid, value = value, permission_read = public and 1 or 0, permission_write = 0 },
  })
  if not ok then nk.logger_warn(string.format("store: %s/%s write failed: %s", collection, key, tostring(err))) end
  return ok
end

function M.delete(collection, key, uid)
  pcall(nk.storage_delete, { { collection = collection, key = key, user_id = uid } })
end

-- Every value of a system-owned collection (up to `limit`, default 2000), as { key, value }.
function M.list(collection, uid, limit)
  local out, cursor = {}, ""
  limit = limit or 2000
  repeat
    local ok, objects, next_cursor = pcall(nk.storage_list, uid, collection, 100, cursor)
    if not ok then break end
    for _, o in ipairs(objects or {}) do
      if type(o.value) == "table" then table.insert(out, { key = o.key, value = o.value, user_id = o.user_id }) end
    end
    cursor = next_cursor or ""
  until cursor == "" or #out >= limit
  return out
end

-- A JSON content file under nakama/content (nil and logged when missing or broken).
function M.content(name)
  local path = "../content/" .. name
  local ok, raw = pcall(nk.file_read, path)
  if not ok then
    nk.logger_warn("content: cannot read " .. path)
    return nil
  end
  local ok2, data = pcall(nk.json_decode, raw)
  if not ok2 or type(data) ~= "table" then
    nk.logger_error("content: " .. path .. " is not valid JSON")
    return nil
  end
  return data
end

return M
