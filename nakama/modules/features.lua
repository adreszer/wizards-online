-- Feature modules: school-life systems that plug into the world match without a
-- protocol op of their own (detention, common-room riddles, clubs, friends, shops,
-- gardens…). Each module under features/ returns
--   { name,
--     requests = { [kind] = function(api, sid, payload) -> data table | nil, reason },
--     join = function(api, sid), leave = function(api, sid), tick = function(api, now),
--     area = function(api, sid, area, previous), event = function(api, sid, ev),
--     caught = function(api, sid), flying = function(api, sid) (a rider's state, once a second),
--     allow = function(api, what, ...) -> false, reason to forbid ("take_item", sid, id) }   (all optional)
-- A client's OP_REQUEST {rid, req, ...} goes to the module that serves `req`, and the
-- answer goes back as OP_REPLY {rid, req, ok, reason, data}. Modules push state with
-- api.push(kind, data, sids) (OP_PUSH) and translated notices with api.notice.
-- `api` (built by world_match.lua) is the only way a module touches the match: it
-- carries the dispatcher-bound helpers (points, coins, items, texts, rumours) and
-- read access to the match state.

local M = {}

M.MODULES = {
  require("features.detention"),
  require("features.common_rooms"),
  require("features.heads"),
  require("features.dormitory"),
  require("features.echoes"),
  require("features.wing"),
  require("features.explore"),
  require("features.friends"),
  require("features.clubs"),
  require("features.games"),
  require("features.ladder"),
  require("features.profiles"),
  require("features.events"),
  require("features.flying"),
  require("features.lantern_chase"),
  require("features.guardians"),
  require("features.garden"),
  require("features.potions"),
  require("features.creatures"),
  require("features.shops"),
  require("features.classroom"),
  require("features.chatlog"),
  require("features.admin"),
  require("features.plans"),
  require("features.analytics"),
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
  local fn = by_kind[payload.req]
  if not fn then return false, "unknown_request", {} end
  local ok, data, reason = pcall(fn, api, sid, payload)
  if not ok then
    api.nk.logger_error(string.format("feature request %s failed: %s", tostring(payload.req), tostring(data)))
    return false, "server_error", {}
  end
  M.each("requested", api, sid, tostring(payload.req), data ~= nil)
  if data == nil then return false, reason or "refused", {} end
  return true, "", data
end

-- Asks every module with an `allow` hook whether `what` may happen; the first that
-- says no wins. Returns ok, reason.
function M.allow(api, what, ...)
  for _, mod in ipairs(M.MODULES) do
    if mod.allow then
      local ok, allowed, reason = pcall(mod.allow, api, what, ...)
      if ok and allowed == false then return false, reason end
    end
  end
  return true
end

-- The first non-nil answer of hook `name` (nil when no module answers).
function M.first(name, api, ...)
  for _, mod in ipairs(M.MODULES) do
    if mod[name] then
      local ok, v = pcall(mod[name], api, ...)
      if ok and v ~= nil then return v end
    end
  end
  return nil
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
