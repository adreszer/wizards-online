-- The sealed stacks: the library's restricted section is for students with a permission
-- slip (an item a professor grants, /slip name) and for staff. Without one, the stacks'
-- door does not answer an Unbolt or the handle, and the server does not count a student
-- in the stacks (no Echo goals, no mystery steps there) even if they slip in behind
-- someone.

local M = { name = "stacks" }

M.AREAS = { restricted_stacks = true }
M.DOORS = { ["restricted_stacks/door_1"] = true }
M.SLIP = "permission_slip"

function M.permitted(api, sid)
  return api.is_staff(sid) or api.count_item(sid, M.SLIP) > 0
end

function M.allow(api, what, sid, x)
  if what == "enter" and M.AREAS[x] and not M.permitted(api, sid) then return false, "no_permission" end
  if what == "object" and type(x) == "table" and M.DOORS[x.oid] and not M.permitted(api, sid) then return false, "no_permission" end
  return true
end

M.requests = {}

-- Staff: {name} grants a permission slip for the sealed stacks.
M.requests.permission_slip = function(api, sid, payload)
  if not api.is_staff(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  local why = api.give_item(target, M.SLIP)
  if why and why ~= "already_owned" then return nil, why end
  api.notice(target, "SLIP_GRANTED", { api.name(sid) }, 8)
  return { name = api.name(target) }
end

return M
