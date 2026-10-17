-- Subject grades (1-6) from a student's record; mirrors gameplay/school/school_grades.gd.
-- Used by the admin's year advancement (world.lua, RPC admin_advance_years).

local M = {}

M.PASS = 2
M.WEIGHTS = { attendance = 0.25, quiz = 0.25, exam = 0.2, practicals = 0.1, homework = 0.2 }
M.FULL_ATTENDANCE, M.FULL_PRACTICALS, M.MIN_LESSONS = 6, 2, 1

function M.grade(s)
  local lessons = (s.attended or 0) + 0.5 * (s.self_study or 0)
  if lessons < M.MIN_LESSONS then return 0 end
  local parts = {}
  parts.attendance = math.min(1, lessons / M.FULL_ATTENDANCE)
  if (s.quiz_total or 0) > 0 then parts.quiz = (s.quiz_right or 0) / s.quiz_total end
  if (s.exam_total or 0) > 0 then parts.exam = (s.exam_right or 0) / s.exam_total end
  if (s.practicals or 0) > 0 or lessons >= M.FULL_ATTENDANCE then parts.practicals = math.min(1, (s.practicals or 0) / M.FULL_PRACTICALS) end
  if (s.homework_count or 0) > 0 then parts.homework = ((s.homework_points or 0) / s.homework_count - 1) / 5 end
  local total, weight = 0, 0
  for k, v in pairs(parts) do
    total = total + M.WEIGHTS[k] * v
    weight = weight + M.WEIGHTS[k]
  end
  local g = 1 + math.floor(5 * total / weight + 0.5)
  return math.max(1, math.min(6, g))
end

-- Whether a record passes the year: every graded subject at PASS or better, and at
-- least `min_subjects` subjects graded.
function M.passes(record, min_subjects)
  local graded = 0
  for _, s in pairs(record.subjects or {}) do
    local g = M.grade(s)
    if g > 0 then
      graded = graded + 1
      if g < M.PASS then return false, graded end
    end
  end
  return graded >= min_subjects, graded
end

return M
