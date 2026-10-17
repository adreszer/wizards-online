-- Homework: a professor sets a task at the end of a lesson (text and days to hand it
-- in); every student who attended gets it; students submit a written answer before
-- the due date; the professor who set it grades each answer (1–6, the Polish school
-- scale, with a comment). Grades go into the student's record (records.lua) and a
-- passing grade pays coins (economy, source "homework").
--
-- Storage:
--   homework/<id>           system-owned: { id, subject, area, by, by_name, text, set_at, due, students = { uid = name } }
--   homework_answers/<id>   per student, owner-readable: { id, text, at, grade?, comment?, graded_at? }

local nk = require("nakama")
local School = require("school")

local M = {}

M.COLLECTION, M.ANSWERS = "homework", "homework_answers"
M.MAX_TEXT_BYTES = 600
M.MAX_ANSWER_BYTES = 1500
M.MAX_COMMENT_BYTES = 300
M.MIN_GRADE, M.MAX_GRADE, M.PASS_GRADE = 1, 6, 2

function M.read(id)
  if type(id) ~= "string" or #id > 64 then return nil end
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = id, user_id = nil } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return nil
end

-- Sets homework for a closed-or-running lesson. Returns the record or nil, reason.
function M.set(lesson, area, by_uid, by_name, text, due_days, now)
  local clean = School.clean_text(text, M.MAX_TEXT_BYTES)
  if clean == "" then return nil, "no_text" end
  local days = math.floor(tonumber(due_days) or 7)
  if days < 1 or days > 30 then return nil, "bad_due" end
  local students = {}
  for uid, name in pairs(lesson.attendance) do students[uid] = name end
  local hw = { id = nk.uuid_v4(), subject = lesson.subject, area = area, by = by_uid, by_name = by_name, text = clean,
               set_at = now, due = now + days * 86400, students = students }
  local ok, err = pcall(nk.storage_write, {
    { collection = M.COLLECTION, key = hw.id, user_id = nil, value = hw, permission_read = 0, permission_write = 0 },
  })
  if not ok then return nil, tostring(err) end
  return hw
end

local function all_homework()
  local out, cursor = {}, ""
  repeat
    local ok, objects, next_cursor = pcall(nk.storage_list, nil, M.COLLECTION, 100, cursor)
    if not ok then break end
    for _, o in ipairs(objects or {}) do
      if type(o.value) == "table" then table.insert(out, o.value) end
    end
    cursor = next_cursor or ""
  until cursor == "" or #out >= 2000
  table.sort(out, function(a, b) return (a.set_at or 0) > (b.set_at or 0) end)
  return out
end

local function answer_of(uid, id)
  local ok, objects = pcall(nk.storage_read, { { collection = M.ANSWERS, key = id, user_id = uid } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then return objects[1].value end
  return nil
end

-- A student's homework: assignments given to them, newest first, each with their answer.
function M.for_student(uid, limit)
  local out = {}
  for _, hw in ipairs(all_homework()) do
    if hw.students and hw.students[uid] then
      table.insert(out, { id = hw.id, subject = hw.subject, by_name = hw.by_name, text = hw.text, set_at = hw.set_at, due = hw.due,
                          answer = answer_of(uid, hw.id) })
      if #out >= limit then break end
    end
  end
  return out
end

-- Stores a student's answer (until it is graded or due). Returns true or nil, reason.
function M.submit(uid, id, text, now)
  local hw = M.read(id)
  if not hw or not hw.students or not hw.students[uid] then return nil, "not_yours" end
  if now > hw.due then return nil, "past_due" end
  local existing = answer_of(uid, id)
  if existing and existing.grade then return nil, "already_graded" end
  local clean = School.clean_text(text, M.MAX_ANSWER_BYTES)
  if clean == "" then return nil, "empty" end
  local ok, err = pcall(nk.storage_write, {
    { collection = M.ANSWERS, key = id, user_id = uid, value = { id = id, text = clean, at = now }, permission_read = 1, permission_write = 0 },
  })
  if not ok then return nil, tostring(err) end
  return true
end

-- A professor's inbox: their assignments with every submitted answer.
function M.inbox(by_uid, is_admin, limit)
  local out = {}
  for _, hw in ipairs(all_homework()) do
    if hw.by == by_uid or is_admin then
      local answers = {}
      for uid, name in pairs(hw.students or {}) do
        local a = answer_of(uid, hw.id)
        if a then table.insert(answers, { user_id = uid, name = name, text = a.text, at = a.at, grade = a.grade, comment = a.comment }) end
      end
      table.sort(answers, function(x, y) return x.name < y.name end)
      table.insert(out, { id = hw.id, subject = hw.subject, text = hw.text, set_at = hw.set_at, due = hw.due, answers = answers,
                          students = hw.students })
      if #out >= limit then break end
    end
  end
  return out
end

-- Grades one answer. Returns the homework record (for the subject) or nil, reason.
function M.grade(by_uid, is_admin, id, uid, grade, comment, now)
  local hw = M.read(id)
  if not hw then return nil, "no_homework" end
  if hw.by ~= by_uid and not is_admin then return nil, "not_your_homework" end
  local a = answer_of(uid, id)
  if not a then return nil, "no_answer" end
  if a.grade then return nil, "already_graded" end
  grade = math.floor(tonumber(grade) or 0)
  if grade < M.MIN_GRADE or grade > M.MAX_GRADE then return nil, "bad_grade" end
  a.grade, a.comment, a.graded_at = grade, School.clean_text(comment, M.MAX_COMMENT_BYTES), now
  local ok, err = pcall(nk.storage_write, {
    { collection = M.ANSWERS, key = id, user_id = uid, value = a, permission_read = 1, permission_write = 0 },
  })
  if not ok then return nil, tostring(err) end
  return hw, a
end

return M
