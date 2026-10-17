-- Self-study lessons: when a timetabled lesson starts and no professor opens it
-- within the grace period, the school's enchanted quill (placeholder name, see
-- nakama/content/self_study.json "host") runs an automated lesson in the room from
-- the subject's plan: lecture lines, board text, multiple-choice questions marked
-- automatically, a practical on the practice target. It teaches a spell only when
-- the owner lists it in school_rules.json `self_study_spells` (human-led lessons
-- keep the rest). A professor who arrives takes the room over.
--
-- Plan steps (texts are {pl, en}):
--   { say = text, wait? }            a lecture line to the room
--   { board = text, wait? }          what the board shows
--   { quiz = text, choices = {text…}, correct = index (0-based), seconds? }
--                                    a question, closed (and marked) after `seconds`
--   { practical = spell id, hits?, seconds? }   a practical, stopped after `seconds`
-- Pure helpers: the world match owns the lesson and does the sending.

local nk = require("nakama")
local SUBJECTS = require("generated.subjects")

local M = {}

M.PATH = "../content/self_study.json"
M.DEFAULT_WAIT = { say = 9, board = 3, quiz = 45, practical = 120 }
M.PAUSE_AFTER_QUIZ = 6
M.LOCALES = { "pl", "en" }

local function is_text(v)
  if type(v) ~= "table" then return false end
  for _, l in ipairs(M.LOCALES) do
    if type(v[l]) ~= "string" or v[l] == "" then return false end
  end
  return true
end

-- `v` ({pl, en} or a plain string) in `locale`.
function M.text(v, locale)
  if type(v) == "string" then return v end
  if type(v) ~= "table" then return "" end
  return v[locale] or v.pl or ""
end

-- Problems with one subject's plan (empty = fine).
function M.validate(subject, plan)
  local errors = {}
  local def = SUBJECTS.by_id[subject]
  if not def then table.insert(errors, "unknown subject " .. tostring(subject)) return errors end
  if type(plan) ~= "table" or type(plan.steps) ~= "table" or #plan.steps == 0 then
    table.insert(errors, subject .. ": no steps")
    return errors
  end
  for i, s in ipairs(plan.steps) do
    local where = subject .. " step " .. i
    if s.say ~= nil then
      if not is_text(s.say) then table.insert(errors, where .. ": say needs pl and en") end
    elseif s.board ~= nil then
      if not is_text(s.board) then table.insert(errors, where .. ": board needs pl and en") end
    elseif s.quiz ~= nil then
      if not is_text(s.quiz) then table.insert(errors, where .. ": quiz needs pl and en") end
      local choices = type(s.choices) == "table" and s.choices or {}
      if #choices < 2 then table.insert(errors, where .. ": a quiz needs two or more choices") end
      for _, c in ipairs(choices) do
        if not is_text(c) then table.insert(errors, where .. ": every choice needs pl and en") end
      end
      local correct = tonumber(s.correct)
      if not correct or correct < 0 or correct >= #choices then table.insert(errors, where .. ": correct must index a choice") end
    elseif s.practical ~= nil then
      local taught = false
      for _, id in ipairs(def.spells) do
        if id == s.practical then taught = true end
      end
      if not taught then table.insert(errors, where .. ": " .. tostring(s.practical) .. " is not a spell of " .. subject) end
    else
      table.insert(errors, where .. ": unknown step")
    end
  end
  return errors
end

-- Reads the plans; bad ones are logged and left out. { host = text, plans = {subject = plan} }
function M.load()
  local out = { host = { pl = "Pióro Wykładowe", en = "the Lecture Quill" }, plans = {} }
  local ok, raw = pcall(nk.file_read, M.PATH)
  if not ok then
    nk.logger_warn("self-study: cannot read " .. M.PATH .. ", no self-study lessons")
    return out
  end
  local ok2, data = pcall(nk.json_decode, raw)
  if not ok2 or type(data) ~= "table" then
    nk.logger_error("self-study: " .. M.PATH .. " is not valid JSON")
    return out
  end
  if is_text(data.host) then out.host = data.host end
  local count = 0
  for subject, plan in pairs(type(data.plans) == "table" and data.plans or {}) do
    local errors = M.validate(subject, plan)
    if #errors == 0 then
      out.plans[subject] = plan
      count = count + 1
    else
      for _, e in ipairs(errors) do nk.logger_error("self-study: " .. e) end
    end
  end
  nk.logger_info(string.format("self-study: %d plans loaded", count))
  return out
end

-- Starts the plan on an (automated) lesson.
function M.start(lesson, plan, now)
  lesson.auto = { plan = plan, step = 0, next_at = now }
end

-- What the automated lesson does now: a list of actions
--   { "say", text } | { "board", text } | { "quiz", step } | { "close_quiz" }
--   | { "practical", spell, hits } | { "stop_practical" } | { "end" }
function M.tick(lesson, now)
  local auto = lesson.auto
  local actions = {}
  if not auto or now < auto.next_at then return actions end
  if auto.closing == "quiz" then
    table.insert(actions, { "close_quiz" })
    auto.closing = nil
    auto.next_at = now + M.PAUSE_AFTER_QUIZ
    return actions
  elseif auto.closing == "practical" then
    table.insert(actions, { "stop_practical" })
    auto.closing = nil
    auto.next_at = now
  end
  auto.step = auto.step + 1
  local s = auto.plan.steps[auto.step]
  if not s then
    table.insert(actions, { "end" })
    lesson.auto = nil
    return actions
  end
  if s.say ~= nil then
    table.insert(actions, { "say", s.say })
    auto.next_at = now + (tonumber(s.wait) or M.DEFAULT_WAIT.say)
  elseif s.board ~= nil then
    table.insert(actions, { "board", s.board })
    auto.next_at = now + (tonumber(s.wait) or M.DEFAULT_WAIT.board)
  elseif s.quiz ~= nil then
    table.insert(actions, { "quiz", s })
    auto.closing = "quiz"
    auto.next_at = now + (tonumber(s.seconds) or M.DEFAULT_WAIT.quiz)
  elseif s.practical ~= nil then
    table.insert(actions, { "practical", s.practical, math.max(1, math.min(10, math.floor(tonumber(s.hits) or 3))) })
    auto.closing = "practical"
    auto.next_at = now + (tonumber(s.seconds) or M.DEFAULT_WAIT.practical)
  end
  return actions
end

-- Whether `spell` may be taught by self-study (school_rules.json self_study_spells).
function M.may_teach(rules, spell)
  for _, id in ipairs(type(rules.self_study_spells) == "table" and rules.self_study_spells or {}) do
    if id == spell then return true end
  end
  return false
end

return M
