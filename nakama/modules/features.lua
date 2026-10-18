-- Feature modules: school-life systems that plug into the world match without a
-- protocol op of their own (detention, common-room riddles, clubs, friends, shops,
-- gardens…). Each module under features/ returns
--   { name,
--     requests = { [kind] = function(api, sid, payload) -> data table | nil, reason },
--     join = function(api, sid), leave = function(api, sid), tick = function(api, now),
--     area = function(api, sid, area, previous), event = function(api, sid, ev),
--     caught = function(api, sid), duel_over = function(api, duel) }   (all optional)
-- A client's OP_REQUEST {id, kind, ...} goes to the module that serves `kind`, and the
-- answer goes back as OP_REPLY {id, kind, ok, reason, data}. Modules push state with
-- api.push(kind, data, sids) (OP_PUSH) and translated notices with api.notice.
-- `api` (built by world_match.lua) is the only way a module touches the match: it
-- carries the dispatcher-bound helpers (points, coins, items, texts, rumours) and
-- read access to the match state.

local M = {}

M.MODULES = {
  require("features.detention"),
  require("features.common_rooms"),
  require("features.heads"),
}

local by_kind = {}
for _, mod in ipairs(M.MODULES) do
  for kind, fn in pairs(mod.requests or {}) do
    assert(not by_kind[kind], "two feature modules serve " .. kind)
    by_kind[kind] = fn
  end
end

-- The answer to a request: ok, reason, data.
function M.request(api, sid, payload)
  local fn = by_kind[payload.kind]
  if not fn then return false, "unknown_request", {} end
  local ok, data, reason = pcall(fn, api, sid, payload)
  if not ok then
    api.nk.logger_error(string.format("feature request %s failed: %s", tostring(payload.kind), tostring(data)))
    return false, "server_error", {}
  end
  if data == nil then return false, reason or "refused", {} end
  return true, "", data
end

-- Runs hook `name` of every module that has it.
function M.each(name, api, ...)
  for _, mod in ipairs(M.MODULES) do
    local fn = mod[name]
    if fn then
      local ok, err = pcall(fn, api, ...)
      if not ok then api.nk.logger_error(string.format("feature %s.%s failed: %s", mod.name or "?", name, tostring(err))) end
    end
  end
end

return M
