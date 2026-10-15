-- The school timetable in real time (nakama/content/timetable.json). Slots are
-- weekly ("mon 18:00, 45 min, Charms") in the school's own time zone; the match
-- turns them into concrete start/end times (seconds since the epoch) for the
-- next days and sends those as OP_TIMETABLE, so clients need no time zone rules
-- and every client rings the same bell at the same moment.

local nk = require("nakama")
local SUBJECTS = require("generated.subjects")
local AREAS = require("world_areas")

local M = {}

M.PATH = "../content/timetable.json"
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

-- Reads and validates the timetable; bad slots are logged and left out.
function M.load()
  local tt = { utc_offset_minutes = 60, dst = "", days_ahead = 7, slots = {} }
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
  local seen = {}
  for _, raw in ipairs(type(data.slots) == "table" and data.slots or {}) do
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
    for _, slot in ipairs(tt.slots) do
      if slot.day == wd then
        local local_start = d * 86400 + slot.start
        local t0 = local_start - M.offset_at(tt, local_start - tt.utc_offset_minutes * 60)
        local t1 = t0 + slot.seconds
        if t1 > now then
          table.insert(out, { id = slot.id, kind = slot.kind, subject = slot.subject, area = slot.area,
                              professor = slot.professor, t0 = t0, t1 = t1 })
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

-- OP_TIMETABLE payload: the school's current UTC offset (minutes, for showing
-- times in school time) and the occurrences.
function M.payload(tt, now)
  local list = {}
  for _, o in ipairs(M.occurrences(tt, now)) do
    table.insert(list, { id = o.id, k = o.kind, s = o.subject, a = o.area, p = o.professor, t0 = o.t0, t1 = o.t1 })
  end
  return nk.json_encode({ tz = math.floor(M.offset_at(tt, now) / 60), slots = list })
end

return M
