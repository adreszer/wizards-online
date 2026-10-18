-- Potion brewing: at a cauldron in the Potions classroom a student adds ingredients
-- they carry (each is used up), stirs, sets the heat, waits and bottles. The server
-- keeps the brew and compares it with the recipes (nakama/content/potions.json): the
-- right steps in the right order, then at least the recipe's wait before bottling.
-- A match gives the potion with a quality (6 when bottled within QUALITY_WINDOW seconds
-- of the wait, lower later, never below 3); anything else is a grey sludge. A professor
-- teaching in the room is told how each student did, and a brew in a lesson counts as a
-- practical in the student's record.
-- Drinking a potion (anywhere) starts its effect for everyone to see: glowing, falling
-- like a feather, a squeaky voice, a different robe colour, a burst of confetti.
--
-- Memory only: state.features.brews[sid] = { steps = {...}, last = time }
--              state.features.effects[sid] = { effect, until }
-- Push "recipes": { recipes } on join; "brew": { steps } to the brewer; "effects": { [name] = { effect, until } } to everyone.

local Store = require("store")
local Records = require("records")
local Wing = require("features.wing")

local M = { name = "potions" }

M.AREA = "class_elixirs"
M.MAX_STEPS = 12
M.QUALITY_WINDOW = 15
M.STEP_GAP = 0.4

local content
local function recipes()
  if not content then
    local data = Store.content("potions.json")
    content = data and type(data.recipes) == "table" and data.recipes or {}
  end
  return content
end

local function brews(api)
  api.state.features.brews = api.state.features.brews or {}
  return api.state.features.brews
end

local function effects(api)
  api.state.features.effects = api.state.features.effects or {}
  return api.state.features.effects
end

-- A brew's steps folded the way recipes are written: consecutive stirs counted together.
function M.fold(steps)
  local out = {}
  for _, s in ipairs(steps) do
    local last = out[#out]
    if s.stir and last and last.stir then
      last.stir = last.stir + 1
    elseif s.stir then
      table.insert(out, { stir = 1 })
    else
      table.insert(out, s)
    end
  end
  return out
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if (x.add or "") ~= (y.add or "") or (x.stir or 0) ~= (y.stir or 0) or (x.heat or "") ~= (y.heat or "") then return false end
  end
  return true
end

-- Which recipe the brew is, or nil.
function M.match(steps)
  local folded = M.fold(steps)
  for id, r in pairs(recipes()) do
    if same(folded, r.steps or {}) then return id, r end
  end
  return nil
end

function M.quality(waited, wait)
  if waited < wait then return 0 end
  local late = waited - wait - M.QUALITY_WINDOW
  if late <= 0 then return 6 end
  return math.max(3, 6 - math.floor(late / 20) - 1)
end

local function effect_view(api)
  local out = {}
  for s, e in pairs(effects(api)) do
    if e["until"] > api.now and api.online(s) then out[api.name(s)] = { effect = e.effect, ["until"] = e["until"] } end
  end
  return out
end

local function send_brew(api, sid)
  local b = brews(api)[sid]
  api.push("brew", { steps = b and b.steps or {} }, sid)
end

function M.join(api, sid)
  api.push("recipes", { recipes = recipes() }, sid)
  api.push("effects", effect_view(api), sid)
end

function M.leave(api, sid)
  brews(api)[sid] = nil
  if effects(api)[sid] then
    effects(api)[sid] = nil
    api.push("effects", effect_view(api), nil)
  end
end

function M.tick(api, now)
  local changed = false
  for s, e in pairs(effects(api)) do
    if e["until"] <= now then
      effects(api)[s] = nil
      changed = true
    end
  end
  if changed then api.push("effects", effect_view(api), nil) end
end

-- Chat lines of a student under the squeaky-voice potion carry voice = "squeak".
function M.chat_voice(api, sid)
  if M.under(api, sid, "voice") then return "squeak" end
  return nil
end

-- Whether `sid` is under `effect` now (other modules: the squeaky voice in chat).
function M.under(api, sid, effect)
  local e = effects(api)[sid]
  return e ~= nil and e.effect == effect and e["until"] > api.now
end

-- One brewing step: {add = item} | {stir = true} | {heat = "low" | "high"}.
local function step(api, sid, s)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local b = brews(api)[sid] or { steps = {} }
  brews(api)[sid] = b
  if b.last and api.now - b.last < M.STEP_GAP then return nil, "too_fast" end
  if #b.steps >= M.MAX_STEPS then return nil, "too_many" end
  if s.add then
    local def = api.ITEMS[s.add]
    if not def or (def.category ~= "herb" and def.category ~= "ingredient") then return nil, "not_an_ingredient" end
    if not api.take_item(sid, s.add, 1) then return nil, "not_owned" end
  end
  table.insert(b.steps, s)
  b.last = api.now
  send_brew(api, sid)
  return { steps = #b.steps }
end

M.requests = {}

M.requests.brew_add = function(api, sid, payload) return step(api, sid, { add = tostring(payload.item or "") }) end
M.requests.brew_stir = function(api, sid, payload) return step(api, sid, { stir = 1 }) end
M.requests.brew_heat = function(api, sid, payload)
  local level = payload.level == "high" and "high" or "low"
  return step(api, sid, { heat = level })
end

M.requests.brew_empty = function(api, sid, payload)
  brews(api)[sid] = nil
  send_brew(api, sid)
  return {}
end

M.requests.brew_bottle = function(api, sid, payload)
  if api.area(sid) ~= M.AREA then return nil, "wrong_room" end
  local b = brews(api)[sid]
  if not b or #b.steps == 0 then return nil, "empty_cauldron" end
  local id, r = M.match(b.steps)
  local waited = api.now - (b.last or api.now)
  if id and waited < (tonumber(r.wait) or 0) then return nil, "not_ready" end
  brews(api)[sid] = nil
  send_brew(api, sid)
  local quality = id and M.quality(waited, tonumber(r.wait) or 0) or 0
  if id then api.give_item(sid, id) end
  Wing.contribute(api, id and 2 or 0)
  -- In a lesson: the professor hears how it went and it counts as a practical.
  local lesson = api.state.lessons[M.AREA]
  if lesson then
    if lesson.by_sid and api.online(lesson.by_sid) then
      api.notice(lesson.by_sid, id and "BREW_REPORT" or "BREW_REPORT_FAILED", { api.name(sid), id and ("ITEM_" .. id:upper() .. "_NAME") or "", quality }, 6)
    end
    if id then Records.practical_done(api.uid(sid), lesson.subject) end
  end
  return { potion = id or "", quality = quality }
end

-- {item}: drink a potion you carry.
M.requests.potion_drink = function(api, sid, payload)
  local id = tostring(payload.item or "")
  local def = api.ITEMS[id]
  if not def or def.category ~= "potion" or (def.effect or "") == "" then return nil, "not_a_potion" end
  if not api.take_item(sid, id, 1) then return nil, "not_owned" end
  effects(api)[sid] = { effect = def.effect, ["until"] = api.now + (tonumber(def.effect_seconds) or 60) }
  api.push("effects", effect_view(api), nil)
  return { effect = def.effect, ["until"] = effects(api)[sid]["until"] }
end

return M
