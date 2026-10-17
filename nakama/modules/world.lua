-- Server module: shared world discovery + chat validation.
-- Loaded once per Lua VM, so it keeps no module-level state; the world match
-- is discovered by label through match_list and created on demand.

local nk = require("nakama")
local Profile = require("character_profile")
local P = require("generated.protocol")
local School = require("school")
local Economy = require("economy")
local Records = require("records")
local Homework = require("homework")
local Timetable = require("timetable")
local Grades = require("grades")

local WORLD_LABEL = "world"

local function find_or_create_world()
  local matches = nk.match_list(1, true, WORLD_LABEL, 0, 200, "")
  if matches and #matches > 0 then
    return matches[1].match_id
  end
  return nk.match_create("world_match", {})
end

-- RPC "join_world": returns the id of the shared world match.
local function rpc_join_world(context, payload)
  local match_id = find_or_create_world()
  return nk.json_encode({ match_id = match_id })
end
nk.register_rpc(rpc_join_world, P.RPC_JOIN_WORLD)

-- Chat goes through the world match (chat.lua decides who hears a line), so Nakama's
-- own channels are closed: a client posting to a room would otherwise reach everyone.
local function before_channel_message_send(context, payload)
  return nil
end
nk.register_rt_before(before_channel_message_send, "ChannelMessageSend")

-- RPC "admin_set_profile": {user_id | name, role?, house?, forget_spells?, forget_mysteries?, reset_inventory?, reset_purse?} → changes a
-- character's role and/or house (and can wipe its spellbook, discoveries and mystery progress for testing). Allowed for server-to-server calls (HTTP key,
-- no session), for users listed in ADMIN_USER_IDS and for admins by profile.
-- The change is applied by the world match (so an online player is updated
-- live and by display name); an offline target is written to storage here.
local function require_admin(context)
  if context.user_id and context.user_id ~= "" then
    local admins = Profile.env_admins(context.env)
    if not admins[context.user_id] then
      local caller = Profile.load(context.user_id)
      if caller.role ~= "admin" then
        error({ "only admins may do this", 7 })  -- 7 = PERMISSION_DENIED
      end
    end
  end
end

local function rpc_admin_set_profile(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  if not ok or type(data) ~= "table" then
    error({ "invalid payload", 3 })  -- 3 = INVALID_ARGUMENT
  end
  if data.role ~= nil and not Profile.ROLES[data.role] then
    error({ "unknown role", 3 })
  end
  if data.house ~= nil and (type(data.house) ~= "number" or data.house < 0 or data.house > Profile.MAX_HOUSE) then
    error({ "house must be 0.." .. Profile.MAX_HOUSE, 3 })
  end
  if data.year ~= nil and (type(data.year) ~= "number" or data.year < 1 or data.year > Profile.MAX_YEAR) then
    error({ "year must be 1.." .. Profile.MAX_YEAR, 3 })
  end
  local request = { op = "set_profile", user_id = data.user_id, name = data.name, role = data.role, house = data.house, year = data.year, forget_spells = data.forget_spells == true, forget_mysteries = data.forget_mysteries == true, reset_inventory = data.reset_inventory == true, reset_purse = data.reset_purse == true }
  local match_id = find_or_create_world()
  local result = nk.match_signal(match_id, nk.json_encode(request))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" then
    error({ "match did not answer", 13 })
  end
  if not decoded.ok and decoded.reason == "offline" and type(data.user_id) == "string" and data.user_id ~= "" then
    local ok_users, users = pcall(nk.users_get_id, { data.user_id })
    if not ok_users or not users or #users == 0 then
      error({ "no such user", 5 })
    end
    local profile = Profile.load(data.user_id)
    if data.role then profile.role = data.role end
    if data.house then profile.house = data.house end
    if data.year then profile.year = math.floor(data.year) end
    if data.forget_spells == true then profile.spells = Profile.sanitize_spells(nil) end
    if data.forget_mysteries == true then
      profile.discoveries = {}
      pcall(nk.storage_delete, { { collection = "mysteries", key = "progress", user_id = data.user_id } })
    end
    if data.reset_inventory == true then
      -- The next join recreates the starting kit.
      pcall(nk.storage_delete, { { collection = "inventory", key = "items", user_id = data.user_id } })
    end
    if data.reset_purse == true then
      Economy.reset(data.user_id, "admin")
    end
    Profile.write(data.user_id, profile)
    decoded = { ok = true, user_id = data.user_id, role = profile.role, house = profile.house, offline = true }
  end
  if not decoded.ok then
    error({ decoded.reason or "failed", 5 })  -- 5 = NOT_FOUND
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_set_profile, P.RPC_ADMIN_SET_PROFILE)

-- RPC "admin_reset_world": {} → every world object back to its default and every
-- world/house mystery unsolved (dev tooling and tests). Admins or the HTTP key.
local function rpc_admin_reset_world(context, payload)
  require_admin(context)
  local result = nk.match_signal(find_or_create_world(), nk.json_encode({ op = "reset_world" }))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" or not decoded.ok then
    error({ "match did not answer", 13 })
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_reset_world, P.RPC_ADMIN_RESET_WORLD)

-- RPC "admin_reload_timetable": {} → {ok, slots}: re-reads nakama/content/timetable.json
-- and sends the new week to everyone. Admins or the HTTP key.
local function rpc_admin_reload_timetable(context, payload)
  require_admin(context)
  local result = nk.match_signal(find_or_create_world(), nk.json_encode({ op = "reload_timetable" }))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" or not decoded.ok then
    error({ "match did not answer", 13 })
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_reload_timetable, P.RPC_ADMIN_RELOAD_TIMETABLE)

-- RPC "house_points_ledger": {limit?} → {records, totals}: the stored record of
-- every house points change, newest first (admins or the HTTP key).
local function rpc_house_points_ledger(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  local limit = ok and type(data) == "table" and tonumber(data.limit) or 50
  return nk.json_encode({ records = School.list_ledger(math.max(1, math.min(500, math.floor(limit)))), totals = School.load_totals() })
end
nk.register_rpc(rpc_house_points_ledger, P.RPC_HOUSE_POINTS_LEDGER)

local function require_staff(context)
  if not context.user_id or context.user_id == "" then
    error({ "lesson plans belong to a professor's session", 3 })
  end
  if not Profile.env_admins(context.env)[context.user_id] and not Profile.is_staff(Profile.load(context.user_id).role) then
    error({ "only professors keep lesson plans", 7 })
  end
end

-- RPC "lesson_plan_save": {id?, title, lines} → {id}. Plans are stored per
-- professor (owner-readable, written only here), never in the game build.
local function rpc_lesson_plan_save(context, payload)
  require_staff(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  local id, err = School.save_plan(context.user_id, ok and data or nil, School.load_rules().max_lecture_bytes)
  if not id then
    error({ err, 3 })
  end
  return nk.json_encode({ id = id })
end
nk.register_rpc(rpc_lesson_plan_save, P.RPC_LESSON_PLAN_SAVE)

-- RPC "lesson_plan_list": {} → {plans = {{id, title, lines}}} for the caller.
local function rpc_lesson_plan_list(context, payload)
  require_staff(context)
  return nk.json_encode({ plans = School.list_plans(context.user_id) })
end
nk.register_rpc(rpc_lesson_plan_list, P.RPC_LESSON_PLAN_LIST)

-- RPC "admin_grant_coins": {user_id | name, amount, reason} → {ok, user_id, coins}: adds
-- (amount > 0) or takes (amount < 0) coins with a reason in the wallet ledger. An online
-- player is changed through the world match (their purse updates at once); an offline
-- one by user id here. Admins or the HTTP key.
local function rpc_admin_grant_coins(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  if not ok or type(data) ~= "table" then
    error({ "invalid payload", 3 })
  end
  local rules = School.load_rules()
  local amount = data.amount
  if type(amount) ~= "number" or amount ~= math.floor(amount) or amount == 0 or math.abs(amount) > rules.max_coin_grant then
    error({ "amount must be a whole number, not 0, at most " .. rules.max_coin_grant, 3 })
  end
  local reason = School.clean_text(data.reason, rules.max_reason_bytes)
  if reason == "" then
    error({ "a reason is required", 3 })
  end
  local by_name = ""
  if context.user_id and context.user_id ~= "" then
    by_name = context.username or ""
  end
  local request = { op = "grant_coins", user_id = data.user_id, name = data.name, amount = amount, reason = reason, by_name = by_name }
  local result = nk.match_signal(find_or_create_world(), nk.json_encode(request))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" then
    error({ "match did not answer", 13 })
  end
  if not decoded.ok and decoded.reason == "offline" and type(data.user_id) == "string" and data.user_id ~= "" then
    local ok_users, users = pcall(nk.users_get_id, { data.user_id })
    -- The nil id is Nakama's system user, never a player.
    if not ok_users or not users or #users == 0 or data.user_id == "00000000-0000-0000-0000-000000000000" then
      error({ "no such user", 5 })
    end
    local done, balance, why = Economy.change(data.user_id, amount, { source = "admin", reason = reason, by_name = by_name })
    decoded = { ok = done, reason = why, user_id = data.user_id, coins = balance, offline = true }
  end
  if not decoded.ok then
    error({ decoded.reason or "failed", decoded.reason == "insufficient" and 9 or 5 })  -- 9 = FAILED_PRECONDITION
  end
  return nk.json_encode(decoded)
end
nk.register_rpc(rpc_admin_grant_coins, P.RPC_ADMIN_GRANT_COINS)

-- RPC "wallet_ledger": {limit?, user_id?} → {coins, entries}: the caller's own purse and
-- its history, newest first; admins (or the HTTP key) may name any user_id.
local function rpc_wallet_ledger(context, payload)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  data = ok and type(data) == "table" and data or {}
  local uid = context.user_id
  if type(data.user_id) == "string" and data.user_id ~= "" and data.user_id ~= uid then
    require_admin(context)
    uid = data.user_id
  end
  if not uid or uid == "" then
    error({ "name a user_id", 3 })
  end
  return nk.json_encode({ coins = Economy.balance(uid), entries = Economy.ledger(uid, data.limit) })
end
nk.register_rpc(rpc_wallet_ledger, P.RPC_WALLET_LEDGER)

-- RPC "school_record": {user_id?} → {user_id, record}: a student's school record
-- (attendance and quiz results per subject, recent lessons). Your own; staff may read
-- any student's (grading), admins and the HTTP key too.
local function rpc_school_record(context, payload)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  data = ok and type(data) == "table" and data or {}
  local uid = context.user_id
  if type(data.user_id) == "string" and data.user_id ~= "" and data.user_id ~= uid then
    if uid and uid ~= "" and not Profile.env_admins(context.env)[uid] and not Profile.is_staff(Profile.load(uid).role) then
      error({ "only staff read other students' records", 7 })
    end
    uid = data.user_id
  end
  if not uid or uid == "" then
    error({ "name a user_id", 3 })
  end
  return nk.json_encode({ user_id = uid, record = Records.load(uid) })
end
nk.register_rpc(rpc_school_record, P.RPC_SCHOOL_RECORD)

-- RPC "lesson_log": {limit?} → {entries}: every lesson held (with attendance) and
-- every timetabled lesson nobody ran, newest first. Admins or the HTTP key.
local function rpc_lesson_log(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  local limit = ok and type(data) == "table" and tonumber(data.limit) or 50
  return nk.json_encode({ entries = Records.list_log(math.max(1, math.min(500, math.floor(limit)))) })
end
nk.register_rpc(rpc_lesson_log, P.RPC_LESSON_LOG)

local function homework_caller(context)
  if not context.user_id or context.user_id == "" then error({ "needs a player session", 3 }) end
  local is_admin = Profile.env_admins(context.env)[context.user_id] or Profile.load(context.user_id).role == "admin"
  return context.user_id, is_admin
end

-- RPC "homework_list": {} → {homework}: the caller's assignments with their answers.
nk.register_rpc(function(context, payload)
  local uid = homework_caller(context)
  return nk.json_encode({ homework = Homework.for_student(uid, 50) })
end, P.RPC_HOMEWORK_LIST)

-- RPC "homework_submit": {id, text} → {ok}.
nk.register_rpc(function(context, payload)
  local uid = homework_caller(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  data = ok and type(data) == "table" and data or {}
  local done, why = Homework.submit(uid, data.id, data.text, nk.time() / 1000)
  if not done then error({ why or "failed", 3 }) end
  return nk.json_encode({ ok = true })
end, P.RPC_HOMEWORK_SUBMIT)

-- RPC "homework_inbox": {} → {homework}: what the calling professor set, with answers.
nk.register_rpc(function(context, payload)
  require_staff(context)
  local uid, is_admin = homework_caller(context)
  return nk.json_encode({ homework = Homework.inbox(uid, is_admin, 50) })
end, P.RPC_HOMEWORK_INBOX)

-- RPC "homework_grade": {id, user_id, grade, comment} → {ok}: grades an answer, records it
-- and pays a passing one.
nk.register_rpc(function(context, payload)
  require_staff(context)
  local by, is_admin = homework_caller(context)
  local ok, data = pcall(nk.json_decode, payload or "")
  data = ok and type(data) == "table" and data or {}
  local now = nk.time() / 1000
  local hw, answer = Homework.grade(by, is_admin, data.id, data.user_id, data.grade, data.comment, now)
  if not hw then error({ answer or "failed", 3 }) end
  Records.homework_graded(data.user_id, hw.subject, answer.grade)
  if answer.grade >= Homework.PASS_GRADE then
    local rules = School.load_rules()
    Economy.earn(data.user_id, rules.coins_per_homework, { source = "homework", subject = hw.subject, reason = "homework" }, rules,
      Timetable.school_day(Timetable.load(), now))
  end
  return nk.json_encode({ ok = true, grade = answer.grade })
end, P.RPC_HOMEWORK_GRADE)

-- RPC "admin_advance_years": {dry_run?, min_subjects?} → {promoted, kept}: every student
-- (everyone who ever joined, from the chat name index) whose graded subjects all pass
-- moves up a year (at most the seventh). Online players are updated live. Admins or the
-- HTTP key. When this runs (end of the school year, after exams) is the owner's call.
nk.register_rpc(function(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  data = ok and type(data) == "table" and data or {}
  local min_subjects = math.max(1, math.floor(tonumber(data.min_subjects) or 3))
  local promoted, kept, cursor = {}, 0, ""
  repeat
    local ok2, objects, next_cursor = pcall(nk.storage_list, nil, "names", 100, cursor)
    if not ok2 then break end
    for _, o in ipairs(objects or {}) do
      local uid = type(o.value) == "table" and o.value.uid
      if uid then
        local profile = Profile.load(uid)
        local passes = Grades.passes(Records.load(uid), min_subjects)
        if profile.role == "student" and passes and profile.year < Profile.MAX_YEAR then
          table.insert(promoted, { user_id = uid, name = o.value.name, year = profile.year + 1 })
          if not data.dry_run then
            local result = nk.match_signal(find_or_create_world(), nk.json_encode({ op = "set_profile", user_id = uid, year = profile.year + 1 }))
            local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
            if type(decoded) ~= "table" or not decoded.ok then
              profile.year = profile.year + 1
              Profile.write(uid, profile)
            end
          end
        else
          kept = kept + 1
        end
      end
    end
    cursor = next_cursor or ""
  until cursor == ""
  return nk.json_encode({ promoted = promoted, kept = kept, dry_run = data.dry_run == true })
end, P.RPC_ADMIN_ADVANCE_YEARS)

-- RPC "admin_award_cup": {term?} → {winner, totals}: the house cup now (the match also
-- awards it by itself after each calendar term). Admins or the HTTP key.
nk.register_rpc(function(context, payload)
  require_admin(context)
  local ok, data = pcall(nk.json_decode, payload ~= "" and payload or "{}")
  data = ok and type(data) == "table" and data or {}
  local result = nk.match_signal(find_or_create_world(), nk.json_encode({ op = "award_cup", term = data.term }))
  local decoded = result and select(2, pcall(nk.json_decode, result)) or nil
  if type(decoded) ~= "table" or not decoded.ok then error({ "match did not answer", 13 }) end
  return nk.json_encode(decoded)
end, P.RPC_ADMIN_AWARD_CUP)
