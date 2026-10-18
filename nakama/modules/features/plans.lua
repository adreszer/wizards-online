-- Lesson plans shared between professors: a professor shares one of their plans (with
-- its subject) with the staff room; every professor sees shared plans in their plan
-- list and can teach from one or save a copy of their own. An admin approves at most one
-- shared plan per subject for self-study: when the enchanted quill runs that subject's
-- lesson, it reads the approved plan's lecture lines first (then the subject's own steps).
--
-- Storage: shared_plans/<id> (system): { id, title, lines, subject, owner, owner_name, approved }

local Store = require("store")
local School = require("school")
local SUBJECTS = require("generated.subjects")

local M = { name = "plans" }

M.COLLECTION = "shared_plans"

local function shared()
  local out = {}
  for _, o in ipairs(Store.list(M.COLLECTION, nil, 300)) do
    if type(o.value.id) == "string" then table.insert(out, o.value) end
  end
  table.sort(out, function(a, b) return (a.title or "") < (b.title or "") end)
  return out
end

-- The approved plan's lines for `subject` (lecture lines only), or {}.
function M.approved_lines(subject)
  for _, p in ipairs(shared()) do
    if p.approved and p.subject == subject then
      local lines = {}
      for _, l in ipairs(p.lines or {}) do
        if type(l) == "string" and l:sub(1, 1) ~= "#" and l:sub(1, 1) ~= "?" then table.insert(lines, l) end
      end
      return lines
    end
  end
  return {}
end

-- A self-study plan with the approved lecture lines read first.
function M.with_approved(plan, subject)
  local lines = M.approved_lines(subject)
  if #lines == 0 or type(plan) ~= "table" then return plan end
  local steps = {}
  for _, l in ipairs(lines) do table.insert(steps, { say = l }) end
  for _, s in ipairs(plan.steps or {}) do table.insert(steps, s) end
  return { steps = steps }
end

M.requests = {}

-- Staff: {id, subject?} shares one of my plans.
M.requests.plan_share = function(api, sid, payload)
  if not api.is_staff(sid) then return nil, "not_allowed" end
  local id = tostring(payload.id or "")
  local mine
  for _, p in ipairs(School.list_plans(api.uid(sid))) do
    if p.id == id then mine = p end
  end
  if not mine then return nil, "no_plan" end
  local subject = tostring(payload.subject or "")
  if subject ~= "" and not SUBJECTS.by_id[subject] then return nil, "unknown_subject" end
  local old = Store.read(M.COLLECTION, id, nil) or {}
  Store.write(M.COLLECTION, id, nil, { id = id, title = mine.title, lines = mine.lines, subject = subject, owner = api.uid(sid), owner_name = api.name(sid),
                                       approved = old.approved == true and old.subject == subject })
  return { id = id }
end

-- Staff: {id} withdraws one of my shared plans (admins any).
M.requests.plan_unshare = function(api, sid, payload)
  local p = Store.read(M.COLLECTION, tostring(payload.id or ""), nil)
  if not p then return nil, "no_plan" end
  if p.owner ~= api.uid(sid) and not api.is_admin(sid) then return nil, "not_allowed" end
  Store.delete(M.COLLECTION, p.id, nil)
  return {}
end

M.requests.plans_shared = function(api, sid, payload)
  if not api.is_staff(sid) then return nil, "not_allowed" end
  return { plans = shared() }
end

-- Admins: {id, on} approves a shared plan for its subject's self-study lessons.
M.requests.plan_approve = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local p = Store.read(M.COLLECTION, tostring(payload.id or ""), nil)
  if not p then return nil, "no_plan" end
  if (p.subject or "") == "" then return nil, "no_subject" end
  if payload.on ~= false then
    for _, other in ipairs(shared()) do
      if other.subject == p.subject and other.approved and other.id ~= p.id then
        other.approved = false
        Store.write(M.COLLECTION, other.id, nil, other)
      end
    end
  end
  p.approved = payload.on ~= false
  Store.write(M.COLLECTION, p.id, nil, p)
  return { id = p.id, approved = p.approved }
end

return M
