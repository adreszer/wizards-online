-- School records: what each student has done in school, per subject, and a log
-- of every lesson. The journal reads a student's record; grades and year
-- progression are built from it.
--
-- Storage:
--   records/transcript   per user, owner-readable, written only here:
--     { v = 1, subjects = { [subject] = { attended, self_study, quiz_right, quiz_total, practicals } },
--       recent = { { subject, at, slot, by, kind } } }   (newest first, RECENT_MAX)
--   lesson_log/<uuid>    system-owned, one per lesson (held or not):
--     { kind = "lesson" | "self_study" | "not_held", subject, area, slot, t0,
--       by, by_name, opened_at, closed_at, why, attended = { uid = name }, points }

local nk = require("nakama")

local M = {}

M.COLLECTION, M.KEY = "records", "transcript"
M.LOG_COLLECTION = "lesson_log"
M.RECENT_MAX = 30
M.SUBJECT_FIELDS = { "attended", "self_study", "quiz_right", "quiz_total", "practicals", "homework_count", "homework_points", "exam_right", "exam_total" }

local function blank_subject()
  local s = {}
  for _, f in ipairs(M.SUBJECT_FIELDS) do s[f] = 0 end
  return s
end

-- A clean record from whatever storage held (unknown fields dropped, numbers floored).
function M.sanitize(raw)
  local rec = { v = 1, subjects = {}, recent = {} }
  if type(raw) ~= "table" then return rec end
  if type(raw.subjects) == "table" then
    for id, s in pairs(raw.subjects) do
      if type(id) == "string" and type(s) == "table" then
        local clean = blank_subject()
        for _, f in ipairs(M.SUBJECT_FIELDS) do
          clean[f] = math.max(0, math.floor(tonumber(s[f]) or 0))
        end
        rec.subjects[id] = clean
      end
    end
  end
  if type(raw.recent) == "table" then
    for _, e in ipairs(raw.recent) do
      if type(e) == "table" and #rec.recent < M.RECENT_MAX then
        table.insert(rec.recent, { subject = tostring(e.subject or ""), at = tonumber(e.at) or 0, slot = tostring(e.slot or ""),
                                   by = tostring(e.by or ""), kind = tostring(e.kind or "lesson") })
      end
    end
  end
  return rec
end

function M.load(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = M.COLLECTION, key = M.KEY, user_id = uid } })
  if ok and objects and objects[1] then
    return M.sanitize(objects[1].value)
  end
  return M.sanitize(nil)
end

function M.save(uid, rec)
  local ok, err = pcall(nk.storage_write, {
    { collection = M.COLLECTION, key = M.KEY, user_id = uid, value = rec, permission_read = 1, permission_write = 0 },
  })
  if not ok then
    nk.logger_warn(string.format("records: write failed for %s: %s", uid, tostring(err)))
  end
  return ok
end

-- The subject's counters in `rec`, created on first use.
function M.subject(rec, id)
  if not rec.subjects[id] then rec.subjects[id] = blank_subject() end
  return rec.subjects[id]
end

-- One attended lesson: kind "lesson" (a professor) or "self_study".
function M.lesson_attended(uid, info)
  local rec = M.load(uid)
  local s = M.subject(rec, info.subject)
  if info.kind == "self_study" then
    s.self_study = s.self_study + 1
  else
    s.attended = s.attended + 1
  end
  table.insert(rec.recent, 1, { subject = info.subject, at = info.at, slot = info.slot or "", by = info.by or "", kind = info.kind or "lesson" })
  while #rec.recent > M.RECENT_MAX do table.remove(rec.recent) end
  return M.save(uid, rec)
end

-- Quiz answers marked by the professor (or a self-study lesson): right of total. An
-- exam's answers count as exam results instead.
function M.quiz_result(uid, subject, right, total, exam)
  local rec = M.load(uid)
  local s = M.subject(rec, subject)
  if exam then
    s.exam_right = s.exam_right + right
    s.exam_total = s.exam_total + total
  else
    s.quiz_right = s.quiz_right + right
    s.quiz_total = s.quiz_total + total
  end
  return M.save(uid, rec)
end

-- A practical task finished (the practice target hit enough times).
function M.practical_done(uid, subject)
  local rec = M.load(uid)
  local s = M.subject(rec, subject)
  s.practicals = s.practicals + 1
  return M.save(uid, rec)
end

-- A graded homework answer (grade 1–6).
function M.homework_graded(uid, subject, grade)
  local rec = M.load(uid)
  local s = M.subject(rec, subject)
  s.homework_count = s.homework_count + 1
  s.homework_points = s.homework_points + grade
  return M.save(uid, rec)
end

function M.log_lesson(entry)
  entry.logged_at = nk.time()
  local ok, err = pcall(nk.storage_write, {
    { collection = M.LOG_COLLECTION, key = nk.uuid_v4(), user_id = nil, value = entry, permission_read = 0, permission_write = 0 },
  })
  if not ok then
    nk.logger_error("lesson log write failed: " .. tostring(err))
  end
  return ok
end

-- Most recent log entries first (up to `limit`).
function M.list_log(limit)
  local out, cursor = {}, ""
  repeat
    local ok, objects, next_cursor = pcall(nk.storage_list, nil, M.LOG_COLLECTION, 100, cursor)
    if not ok then break end
    for _, o in ipairs(objects or {}) do
      if type(o.value) == "table" then table.insert(out, o.value) end
    end
    cursor = next_cursor or ""
  until cursor == "" or #out >= 2000
  table.sort(out, function(a, b) return (a.logged_at or 0) > (b.logged_at or 0) end)
  local limited = {}
  for i = 1, math.min(limit, #out) do limited[i] = out[i] end
  return limited
end

return M
