-- Mysteries as data: multi-step secrets defined in nakama/content/mysteries.json,
-- with their text in nakama/content/strings.json. Both files are server-only;
-- clients learn a clue or a solution only when they earn it.
--
-- A mystery is an ordered list of steps; each validated event (a spell on an
-- object, an interaction, entering an area) is matched against the next step.
-- Step kinds:
--   { event = "spell", object, effect_type?, state? }  state: the object's state after the hit
--   { event = "interact", object }
--   { event = "enter", area, holding? }                 holding: item id in hand
--   { event = "together", area, players }               that many players in the area at once
-- Optional per step: within_seconds (since the previous step), text (sent to the actor).
-- Mystery fields: id, scope ("world" | "house" | "player"), steps, reset_on_wrong,
-- reset_after_minutes (world/house), on_solved = { set_state = {oid = state},
-- text, discovery, house_points }.
--
-- The engine only decides; world_match.lua executes the returned actions.

local nk = require("nakama")
local OBJECTS = require("generated.world_objects")
local AREAS = require("world_areas")
local SPELLS = require("generated.spells")
local ITEMS = require("generated.items")

local M = {}

M.CONTENT_PATH = "../content/mysteries.json"
M.STRINGS_PATH = "../content/strings.json"
M.LOCALES = { "pl", "en" }
M.FALLBACK_LOCALE = "pl"
M.SCOPES = { world = true, house = true, player = true }

local function read_json(path)
  local ok, text = pcall(nk.file_read, path)
  if not ok then
    return nil, "cannot read " .. path .. ": " .. tostring(text)
  end
  local ok2, data = pcall(nk.json_decode, text)
  if not ok2 or type(data) ~= "table" then
    return nil, "cannot parse " .. path
  end
  return data
end

local function effect_types()
  local out = {}
  for _, def in pairs(SPELLS.by_id) do
    out[def.effect_type] = true
  end
  return out
end

local function accepts(obj, effect_type)
  for _, t in ipairs(obj.accepts or {}) do
    if t == "any" or t == effect_type then
      return true
    end
  end
  return false
end

-- Returns a list of problems with one mystery (empty when valid).
function M.validate(m, strings, seen)
  local errors = {}
  local function err(msg) table.insert(errors, string.format("mystery %s: %s", tostring(m.id), msg)) end
  local function text_ok(key, where)
    if key == nil then return end
    local entry = strings[key]
    if type(entry) ~= "table" then err(where .. ": unknown text " .. tostring(key)); return end
    for _, loc in ipairs(M.LOCALES) do
      if type(entry[loc]) ~= "string" or entry[loc] == "" then err(where .. ": text " .. key .. " lacks " .. loc) end
    end
  end
  if type(m.id) ~= "string" or m.id == "" then err("missing id") elseif seen[m.id] then err("duplicate id") end
  if not M.SCOPES[m.scope] then err("unknown scope " .. tostring(m.scope)) end
  if type(m.steps) ~= "table" or #m.steps == 0 then err("no steps"); return errors end
  local effects = effect_types()
  for i, step in ipairs(m.steps) do
    local where = "step " .. i
    if step.event == "spell" or step.event == "interact" then
      local obj = OBJECTS[step.object]
      if not obj then
        err(where .. ": unknown object " .. tostring(step.object))
      elseif step.event == "spell" then
        if step.effect_type and not effects[step.effect_type] then err(where .. ": unknown effect type " .. step.effect_type) end
        if step.effect_type and not accepts(obj, step.effect_type) then err(where .. ": " .. step.object .. " does not accept " .. step.effect_type) end
        if #(obj.accepts or {}) == 0 then err(where .. ": " .. step.object .. " takes no spells") end
      end
    elseif step.event == "enter" or step.event == "together" then
      if not AREAS[step.area] then err(where .. ": unknown area " .. tostring(step.area)) end
      if step.holding and not ITEMS.by_id[step.holding] then err(where .. ": unknown item " .. tostring(step.holding)) end
      if step.event == "together" and (type(step.players) ~= "number" or step.players < 2) then err(where .. ": together needs players >= 2") end
    else
      err(where .. ": unknown event " .. tostring(step.event))
    end
    text_ok(step.text, where)
  end
  local solved = m.on_solved or {}
  for oid, _ in pairs(solved.set_state or {}) do
    if not OBJECTS[oid] then err("on_solved: unknown object " .. tostring(oid)) end
  end
  if m.scope == "player" and next(solved.set_state or {}) then err("player-scoped mysteries cannot change shared objects") end
  text_ok(solved.text, "on_solved")
  return errors
end

-- Loads and validates the content. Broken mysteries are logged and left out.
function M.load()
  local engine = { list = {}, strings = {}, driven = {} }
  local strings, serr = read_json(M.STRINGS_PATH)
  if not strings then
    nk.logger_warn("mysteries: " .. serr)
    strings = {}
  end
  engine.strings = strings
  local data, derr = read_json(M.CONTENT_PATH)
  if not data then
    nk.logger_warn("mysteries: " .. derr)
    return engine
  end
  local seen = {}
  for _, m in ipairs(data.mysteries or {}) do
    local errors = M.validate(m, strings, seen)
    if #errors == 0 then
      seen[m.id] = true
      table.insert(engine.list, m)
      for oid, _ in pairs((m.on_solved or {}).set_state or {}) do
        engine.driven[oid] = true
      end
    else
      for _, e in ipairs(errors) do
        nk.logger_error(e)
      end
    end
  end
  nk.logger_info(string.format("mysteries: %d loaded", #engine.list))
  return engine
end

-- Text for a key in the player's locale.
function M.text(engine, key, locale)
  local entry = engine.strings[key]
  if type(entry) ~= "table" then
    return key
  end
  return entry[locale] or entry[M.FALLBACK_LOCALE] or key
end

-- Match-side progress for world and house scopes; player scope lives in each
-- player's stored record (ctx.player_progress).
function M.new_state()
  return { world = {}, house = {} }
end

local function record_for(mstate, m, ev, ctx)
  if m.scope == "world" then
    mstate.world[m.id] = mstate.world[m.id] or { step = 0 }
    return mstate.world[m.id]
  elseif m.scope == "house" then
    if (ev.house or 0) == 0 then return nil end
    mstate.house[ev.house] = mstate.house[ev.house] or {}
    local h = mstate.house[ev.house]
    h[m.id] = h[m.id] or { step = 0 }
    return h[m.id]
  end
  local progress = ctx.player_progress(ev.uid)
  if not progress then return nil end
  progress[m.id] = progress[m.id] or { step = 0 }
  return progress[m.id]
end

local function matches(step, ev, ctx)
  if step.event == "spell" then
    return ev.event == "spell" and ev.object == step.object
      and (step.effect_type == nil or step.effect_type == ev.effect_type)
      and (step.state == nil or step.state == ev.state)
  elseif step.event == "interact" then
    return ev.event == "interact" and ev.object == step.object
  elseif step.event == "enter" then
    return ev.event == "enter" and ev.area == step.area and (step.holding == nil or step.holding == ev.held)
  elseif step.event == "together" then
    return ev.event == "enter" and ev.area == step.area and #ctx.players_in(step.area) >= step.players
  end
  return false
end

local function touches(m, ev)
  for _, step in ipairs(m.steps) do
    if (ev.object and step.object == ev.object) or (ev.event == "enter" and step.area == ev.area) then
      return true
    end
  end
  return false
end

local function reset(record)
  record.step, record.at, record.players = 0, nil, nil
end

-- Feeds one validated event to every mystery. `ev` = { event, object?, area,
-- effect_type?, state?, sid, uid, house, held, now }. `ctx` = { players_in(area)
-- -> list of {sid, uid, house}, player_progress(uid) -> table, progress_changed(uid) }.
-- Returns a list of actions:
--   { "text", sid, key }  { "set_state", oid, value }  { "discovery", sid, id }
--   { "house_points", house, delta, reason }
function M.on_event(engine, mstate, ev, ctx)
  local actions = {}
  for _, m in ipairs(engine.list) do
    local record = record_for(mstate, m, ev, ctx)
    if record and not record.solved then
      local before = record.step
      local step = m.steps[record.step + 1]
      if record.step > 0 and step.within_seconds and ev.now - (record.at or 0) > step.within_seconds then
        reset(record)
        step = m.steps[1]
      end
      if matches(step, ev, ctx) then
        record.step = record.step + 1
        record.at = ev.now
        record.players = record.players or {}
        record.players[ev.uid] = ev.sid
        if step.event == "together" then
          for _, p in ipairs(ctx.players_in(step.area)) do
            record.players[p.uid] = p.sid
          end
        end
        if step.text then
          table.insert(actions, { "text", ev.sid, step.text })
        end
        if record.step == #m.steps then
          record.solved, record.solved_at = true, ev.now
          local solved = m.on_solved or {}
          for oid, value in pairs(solved.set_state or {}) do
            table.insert(actions, { "set_state", oid, value })
          end
          for _, sid in pairs(record.players) do
            if solved.text then table.insert(actions, { "text", sid, solved.text }) end
            if solved.discovery then table.insert(actions, { "discovery", sid, solved.discovery, m.id }) end
          end
          if solved.house_points and (ev.house or 0) > 0 then
            table.insert(actions, { "house_points", ev.house, solved.house_points, "mystery:" .. m.id, ev.sid })
          end
        end
      elseif record.step > 0 and m.reset_on_wrong and touches(m, ev) then
        reset(record)
      end
      if m.scope == "player" and record.step ~= before then
        ctx.progress_changed(ev.uid)
      end
    end
  end
  return actions
end

-- Re-arms solved world/house mysteries after reset_after_minutes, once nobody
-- stands where the reset would change something (a closing wall must not trap
-- anyone). `occupied(area)` -> bool. Returns { "set_state", oid, nil } actions.
function M.tick(engine, mstate, now, occupied)
  local actions = {}
  for _, m in ipairs(engine.list) do
    local minutes = m.reset_after_minutes
    if minutes and m.scope ~= "player" then
      local records = {}
      if m.scope == "world" then
        records = { mstate.world[m.id] }
      else
        for _, h in pairs(mstate.house) do table.insert(records, h[m.id]) end
      end
      for _, record in ipairs(records) do
        if record and record.solved and now - record.solved_at >= minutes * 60 then
          local busy = false
          for oid, _ in pairs((m.on_solved or {}).set_state or {}) do
            for _, a in ipairs(OBJECTS[oid].areas or {}) do
              if occupied(a) then busy = true end
            end
          end
          if not busy then
            record.solved, record.solved_at = nil, nil
            reset(record)
            for oid, _ in pairs((m.on_solved or {}).set_state or {}) do
              table.insert(actions, { "set_state", oid, nil })
            end
          end
        end
      end
    end
  end
  return actions
end

return M
