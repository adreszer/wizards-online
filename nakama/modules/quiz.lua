-- Quizzes in a lesson: the professor asks a question (multiple choice with a correct
-- answer, multiple choice without one, or open), the students in the room answer, the
-- professor sees the answers live and closes the question; multiple-choice answers
-- are marked at once, open ones the professor marks one by one. Marked answers go
-- into each student's school record (records.lua). Pure helpers: the world match
-- owns the lesson and does the sending.

local School = require("school")

local M = {}

M.MAX_QUESTION_BYTES = 300
M.MAX_CHOICE_BYTES = 120
M.MAX_ANSWER_BYTES = 300
M.MAX_CHOICES = 6

-- A clean question from a professor's request, or nil and a reason.
-- choices: 0 (open question) or 2..MAX_CHOICES strings; correct: 0-based index or -1.
function M.new_question(id, payload)
  local question = School.clean_text(payload.question, M.MAX_QUESTION_BYTES)
  if question == "" then return nil, "no_question" end
  local choices = {}
  for _, c in ipairs(type(payload.choices) == "table" and payload.choices or {}) do
    local clean = School.clean_text(c, M.MAX_CHOICE_BYTES)
    if clean ~= "" then table.insert(choices, clean) end
  end
  if #choices == 1 or #choices > M.MAX_CHOICES then return nil, "bad_choices" end
  local correct = tonumber(payload.correct) or -1
  if correct ~= math.floor(correct) or correct < -1 or correct >= #choices then correct = -1 end
  return { id = id, question = question, choices = choices, correct = correct, answers = {}, open = true }
end

-- Records `sid`'s answer (a choice index for multiple choice, text otherwise).
-- Returns the stored answer or nil and a reason. An answer may change while open.
function M.answer(quiz, sid, uid, name, raw)
  if not quiz.open then return nil, "closed" end
  local value
  if #quiz.choices > 0 then
    value = tonumber(raw)
    if not value or value ~= math.floor(value) or value < 0 or value >= #quiz.choices then return nil, "bad_answer" end
  else
    value = School.clean_text(raw, M.MAX_ANSWER_BYTES)
    if value == "" then return nil, "bad_answer" end
  end
  quiz.answers[sid] = { uid = uid, name = name, answer = value }
  return value
end

-- Closes the quiz: with a correct choice every answer is marked right or wrong.
-- Returns the answers marked by this call ({sid = entry}).
function M.close(quiz)
  quiz.open = false
  local marked = {}
  if quiz.correct >= 0 then
    for sid, a in pairs(quiz.answers) do
      if a.right == nil then
        a.right = a.answer == quiz.correct
        marked[sid] = a
      end
    end
  end
  return marked
end

-- The professor marks one answer (open questions, or choices without a correct one).
-- Returns the entry when it was newly marked, else nil and a reason.
function M.mark(quiz, sid, right)
  local a = quiz.answers[sid]
  if not a then return nil, "no_answer" end
  if a.right ~= nil then return nil, "already_marked" end
  a.right = right == true
  return a
end

-- The answers as a list for the professor: { {sid, name, answer, right?} }, by name.
function M.answers_list(quiz)
  local out = {}
  for sid, a in pairs(quiz.answers) do
    table.insert(out, { sid = sid, name = a.name, answer = a.answer, right = a.right })
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  return out
end

-- What one student sees: the question, the choices, their own answer, and once
-- closed the correct choice and whether they were right.
function M.view_for(quiz, sid, by_name)
  local mine = quiz.answers[sid]
  local view = { id = quiz.id, question = quiz.question, choices = quiz.choices, by = by_name, open = quiz.open }
  if mine then
    view.answer = mine.answer
    if mine.right ~= nil then view.right = mine.right end
  end
  if not quiz.open and quiz.correct >= 0 then view.correct = quiz.correct end
  return view
end

return M
