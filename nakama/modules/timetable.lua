-- The school timetable in real time (nakama/content/timetable.json). Slots are
-- weekly ("mon 18:00, 45 min, Charms") in the school's own time zone, and happen
-- only on school days of nakama/content/calendar.json (terms minus breaks; exam
-- weeks are flagged); the match
-- turns them into concrete start/end times (seconds since the epoch) for the
-- next days and sends those as OP_TIMETABLE, so clients need no time zone rules
-- and every client rings the same bell at the same moment.

local nk = require("nakama")
local SUBJECTS = require("generated.subjects")
local AREAS = require("world_areas")

local M = {}

M.PATH = "../content/timetable.json"
-- Terms, breaks and exam weeks (optional: without it every week is a school week).
M.CALENDAR_PATH = "../content/calendar.json"
M.DAYS = { mon = 0, tue = 1, wed = 2, thu = 3, fri = 4, sat = 5, sun = 6 }
M.KINDS = { lesson = true, study = true }
-- Professors' slots may open a few minutes early.
M.EARLY_OPEN_SECONDS = 10 * 60

-- Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
function M.days_from_civil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- Civil year of a day number.
function M.year_of(days)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then y = y + 1 end
  return y
end

-- Weekday of a day number, 0 = Monday (1970-01-01 was a Thursday).
function M.weekday(days)
  return (days + 3) % 7
end

-- Last Sunday of a month at 01:00 UTC, in epoch seconds.
local function last_sunday_utc(y, m)
  local first_next = m == 12 and M.days_from_civil(y + 1, 1, 1) or M.days_from_civil(y, m + 1, 1)
  local last = first_next - 1
  local sunday = last - (M.weekday(last) - 6) % 7
  return sunday * 86400 + 3600
end

-- The school's offset from UTC in seconds at `utc` (EU summer time: last Sunday
-- of March to last Sunday of October, both at 01:00 UTC).
function M.offset_at(tt, utc)
  local offset = tt.utc_offset_minutes * 60
  if tt.dst == "eu" then
    local y = M.year_of(math.floor(utc / 86400))
    if utc >= last_sunday_utc(y, 3) and utc < last_sunday_utc(y, 10) then
      offset = offset + 3600
    end
  end
  return offset
end

local function parse_clock(text)
  if type(text) ~= "string" then return nil end
  local h, m = text:match("^(%d%d?):(%d%d)$")
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  return h * 3600 + m * 60
end

-- Checks one slot; returns the clean slot or nil and a reason.
function M.sanitize_slot(raw)
  if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then return nil, "no id" end
  local kind = raw.kind or "lesson"
  if not M.KINDS[kind] then return nil, "unknown kind " .. tostring(kind) end
  local day = M.DAYS[raw.day]
  if not day then return nil, "unknown day " .. tostring(raw.day) end
  local start = parse_clock(raw.start)
  if not start then return nil, "bad start " .. tostring(raw.start) end
  local minutes = tonumber(raw.minutes)
  if not minutes or minutes < 5 or minutes > 240 then return nil, "bad minutes" end
  local subject = raw.subject
  local room = raw.room
  if kind == "lesson" then
    local def = SUBJECTS.by_id[subject or ""]
    if not def then return nil, "unknown subject " .. tostring(subject) end
    room = room or def.classrooms[1]
  elseif subject ~= nil and not SUBJECTS.by_id[subject] then
    return nil, "unknown subject " .. tostring(subject)
  end
  if type(room) ~= "string" or not AREAS[room] then return nil, "unknown room " .. tostring(room) end
  return {
    id = raw.id, kind = kind, day = day, start = start, seconds = math.floor(minutes) * 60,
    subject = subject or "", area = room, professor = type(raw.professor) == "string" and raw.professor or "",
  }
end

-- "2026-09-01" → day number, or nil.
function M.parse_date(text)
  if type(text) ~= "string" then return nil end
  local y, m, d = text:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  return M.days_from_civil(y, m, d)
end

-- A list of {name_key?, start, end} ranges from the calendar file; bad ones logged.
local function parse_ranges(raw, what, need_key)
  local out = {}
  for i, r in ipairs(type(raw) == "table" and raw or {}) do
    local d0 = type(r) == "table" and M.parse_date(r.start) or nil
    local d1 = type(r) == "table" and M.parse_date(r["end"]) or nil
    local key = type(r) == "table" and type(r.name_key) == "string" and r.name_key or ""
    if not d0 or not d1 or d1 < d0 or (need_key and key == "") then
      nk.logger_error(string.format("calendar: %s %d left out (dates or name_key)", what, i))
    else
      table.insert(out, { id = type(r.id) == "string" and r.id or key, key = key, d0 = d0, d1 = d1 })
    end
  end
  return out
end

-- Reads nakama/content/calendar.json: { terms, breaks, exams } as day ranges.
function M.load_calendar()
  local cal = { terms = {}, breaks = {}, exams = {} }
  local ok, text = pcall(nk.file_read, M.CALENDAR_PATH)
  if not ok then return cal end
  local ok2, data = pcall(nk.json_decode, text)
  if not ok2 or type(data) ~= "table" then
    nk.logger_error("calendar: " .. M.CALENDAR_PATH .. " is not valid JSON")
    return cal
  end
  cal.terms = parse_ranges(data.terms, "term", true)
  cal.breaks = parse_ranges(data.breaks, "break", true)
  cal.exams = parse_ranges(data.exam_weeks, "exam week", false)
  return cal
end

local function range_at(list, day)
  for _, r in ipairs(list) do
    if day >= r.d0 and day <= r.d1 then return r end
  end
  return nil
end

-- What school day number `day` is: { school = lessons happen, term?, brk?, exam }.
-- Without terms in the calendar every day outside a break is a school day.
function M.day_info(tt, day)
  local cal = tt.calendar or { terms = {}, breaks = {}, exams = {} }
  local term = range_at(cal.terms, day)
  local brk = range_at(cal.breaks, day)
  local in_term = term ~= nil or #cal.terms == 0
  return { school = in_term and brk == nil, term = term, brk = brk, exam = range_at(cal.exams, day) ~= nil and in_term and brk == nil }
end

-- The calendar part of OP_TIMETABLE for `day`: the term's name key and week, the
-- break's, whether it is an exam day, and the next term when between terms.
function M.calendar_payload(tt, day)
  local info = M.day_info(tt, day)
  local out = { exam = info.exam }
  if info.term then
    out.term = info.term.key
    out.week = math.floor((day - info.term.d0) / 7) + 1
  end
  if info.brk then out.brk = info.brk.key end
  if not info.term and tt.calendar and #tt.calendar.terms > 0 then
    local next_term
    for _, t in ipairs(tt.calendar.terms) do
      if t.d0 > day and (not next_term or t.d0 < next_term.d0) then next_term = t end
    end
    if next_term then out.next_term, out.next_day = next_term.key, next_term.d0 end
  end
  return out
end

M.OVERRIDES_COLLECTION, M.OVERRIDES_KEY = "school", "timetable_overrides"

-- The in-game timetable changes: { add = { raw slots }, remove = { [id] = true } }.
function M.load_overrides()
  local ok, objects = pcall(nk.storage_read, { { collection = M.OVERRIDES_COLLECTION, key = M.OVERRIDES_KEY, user_id = nil } })
  local v = ok and objects and objects[1] and objects[1].value or {}
  local out = { add = {}, remove = {} }
  if type(v) == "table" then
    if type(v.add) == "table" then
      for _, s in ipairs(v.add) do
        if type(s) == "table" then table.insert(out.add, s) end
      end
    end
    if type(v.remove) == "table" then
      for id, on in pairs(v.remove) do
        if on == true then out.remove[id] = true end
      end
    end
  end
  return out
end

function M.save_overrides(o)
  return pcall(nk.storage_write, { { collection = M.OVERRIDES_COLLECTION, key = M.OVERRIDES_KEY, user_id = nil, value = o, permission_read = 0, permission_write = 0 } })
end

-- Reads and validates the timetable; bad slots are logged and left out.
function M.load()
  local tt = { utc_offset_minutes = 60, dst = "", days_ahead = 7, slots = {}, calendar = M.load_calendar() }
  local ok, text = pcall(nk.file_read, M.PATH)
  if not ok then
    nk.logger_warn("timetable: cannot read " .. M.PATH .. ", no lessons scheduled")
    return tt
  end
  local ok2, data = pcall(nk.json_decode, text)
  if not ok2 or type(data) ~= "table" then
    nk.logger_error("timetable: " .. M.PATH .. " is not valid JSON")
    return tt
  end
  if type(data.utc_offset_minutes) == "number" then tt.utc_offset_minutes = data.utc_offset_minutes end
  if data.dst == "eu" then tt.dst = "eu" end
  if type(data.days_ahead) == "number" then tt.days_ahead = math.max(1, math.min(14, math.floor(data.days_ahead))) end
  -- Changes made in the game (admin panel, features/admin.lua) sit in storage on top of the file:
  -- slots removed by id, slots added (an added slot with a file slot's id replaces it).
  local overrides = M.load_overrides()
  local raws = {}
  for _, raw in ipairs(type(data.slots) == "table" and data.slots or {}) do
    if type(raw) ~= "table" or not overrides.remove[raw.id] then table.insert(raws, raw) end
  end
  for _, raw in ipairs(overrides.add) do table.insert(raws, raw) end
  local seen = {}
  for _, raw in ipairs(raws) do
    local slot, why = M.sanitize_slot(raw)
    if slot and seen[slot.id] then
      slot, why = nil, "duplicate id"
    end
    if slot then
      seen[slot.id] = true
      table.insert(tt.slots, slot)
    else
      nk.logger_error(string.format("timetable: slot %s left out: %s", tostring(type(raw) == "table" and raw.id), why))
    end
  end
  return tt
end

-- Every occurrence that has not ended by `now`, up to days_ahead school days on,
-- sorted by start: { id, kind, subject, area, professor, t0, t1 }.
function M.occurrences(tt, now)
  local out = {}
  local today = math.floor((now + M.offset_at(tt, now)) / 86400)
  for d = today - 1, today + tt.days_ahead do
    local wd = M.weekday(d)
    local info = M.day_info(tt, d)
    for _, slot in ipairs(info.school and tt.slots or {}) do
      if slot.day == wd then
        local local_start = d * 86400 + slot.start
        local t0 = local_start - M.offset_at(tt, local_start - tt.utc_offset_minutes * 60)
        local t1 = t0 + slot.seconds
        if t1 > now then
          table.insert(out, { id = slot.id, kind = slot.kind, subject = slot.subject, area = slot.area,
                              professor = slot.professor, t0 = t0, t1 = t1, exam = info.exam })
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.t0 < b.t0 end)
  return out
end

-- The occurrence of `subject` in `area` that is on now (or opens within
-- EARLY_OPEN_SECONDS), or nil.
function M.current(tt, now, area, subject)
  for _, o in ipairs(M.occurrences(tt, now)) do
    if o.area == area and o.subject == subject and now >= o.t0 - M.EARLY_OPEN_SECONDS and now < o.t1 then
      return o
    end
  end
  return nil
end

-- The day number (school local) that `now` falls on: the match re-sends the
-- timetable when it changes.
function M.school_day(tt, now)
  return math.floor((now + M.offset_at(tt, now)) / 86400)
end

-- The id of the calendar term `now` falls in ("" outside terms).
function M.term_id(tt, now)
  local info = M.day_info(tt, M.school_day(tt, now))
  return info.term and info.term.id or ""
end

-- OP_TIMETABLE payload: the school's current UTC offset (minutes, for showing
-- times in school time) and the occurrences.
function M.payload(tt, now)
  local list = {}
  for _, o in ipairs(M.occurrences(tt, now)) do
    table.insert(list, { id = o.id, k = o.kind, s = o.subject, a = o.area, p = o.professor, t0 = o.t0, t1 = o.t1, x = o.exam or nil })
  end
  return nk.json_encode({ tz = math.floor(M.offset_at(tt, now) / 60), base = tt.utc_offset_minutes, dst = tt.dst, slots = list,
                          cal = M.calendar_payload(tt, M.school_day(tt, now)) })
end

return M
