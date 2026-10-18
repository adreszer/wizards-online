-- Heads of house: an admin names a professor head of a house. The head (and admins)
-- see house-wide numbers (members, this term's points by source, the week's quests)
-- and post to the house board, which every member reads (journal, common-room notice
-- board). Prefects may post too.
--
-- Storage: school/heads (system): { ["1"] = { uid, name }, … }
--          school/house_board_<house> (system): { posts = { { by, text, at } } } newest first, MAX_POSTS
-- Push "house_board": { house, head, posts } to the house's members.

local Store = require("store")
local School = require("school")
local Quests = require("house_quests")

local M = { name = "heads" }

M.COLLECTION = "school"
M.MAX_POSTS = 12
M.MAX_POST_BYTES = 400
M.POST_GAP = 10

local function heads()
  return Store.read(M.COLLECTION, "heads", nil) or {}
end

local function board(house)
  return Store.read(M.COLLECTION, "house_board_" .. house, nil) or { posts = {} }
end

-- Whether `sid` is the head of `house`.
function M.is_head(api, sid, house)
  local h = heads()[tostring(house)]
  return h ~= nil and h.uid == api.uid(sid)
end

local function send(api, house, sids)
  if house < 1 then return end
  local h = heads()[tostring(house)]
  local data = { house = house, head = h and h.name or "", posts = board(house).posts }
  if not sids then
    sids = {}
    for _, sid in ipairs(api.sids()) do
      if api.house(sid) == house then table.insert(sids, sid) end
    end
  end
  api.push("house_board", data, sids)
end

function M.join(api, sid)
  send(api, api.house(sid), { sid })
end

M.requests = {}

-- Admins: {name, house} names a professor head of a house (house 0 = of none).
M.requests.house_head_set = function(api, sid, payload)
  if not api.is_admin(sid) then return nil, "not_allowed" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  if not api.is_staff(target) then return nil, "not_a_professor" end
  local house = math.floor(tonumber(payload.house) or -1)
  if house < 0 or house > 4 then return nil, "bad_house" end
  local all = heads()
  for k, h in pairs(all) do
    if h.uid == api.uid(target) then all[k] = nil end
  end
  if house > 0 then all[tostring(house)] = { uid = api.uid(target), name = api.name(target) } end
  Store.write(M.COLLECTION, "heads", nil, all)
  if house > 0 then send(api, house) end
  return { house = house, name = api.name(target) }
end

-- The head of a house, a prefect of it or an admin: {text, house?} posts to the board.
M.requests.house_board_post = function(api, sid, payload)
  local house = math.floor(tonumber(payload.house) or api.house(sid))
  if house < 1 or house > 4 then return nil, "bad_house" end
  local allowed = api.is_admin(sid) or M.is_head(api, sid, house) or (api.role(sid) == "prefect" and api.house(sid) == house)
  if not allowed then return nil, "not_allowed" end
  local text = School.clean_text(payload.text, M.MAX_POST_BYTES)
  if text == "" then return nil, "empty" end
  local f = api.state.features
  f.board_at = f.board_at or {}
  if f.board_at[sid] and api.now - f.board_at[sid] < M.POST_GAP then return nil, "too_fast" end
  f.board_at[sid] = api.now
  local filtered = require("moderation").filter(text, api.state.filter or {})
  local b = board(house)
  table.insert(b.posts, 1, { by = api.name(sid), text = filtered, at = api.now })
  while #b.posts > M.MAX_POSTS do table.remove(b.posts) end
  Store.write(M.COLLECTION, "house_board_" .. house, nil, b)
  send(api, house)
  return { house = house }
end

-- The head of a house or an admin: {house?} house-wide numbers.
M.requests.house_stats = function(api, sid, payload)
  local house = math.floor(tonumber(payload.house) or 0)
  if house == 0 then
    for k, h in pairs(heads()) do
      if h.uid == api.uid(sid) then house = tonumber(k) end
    end
  end
  if house < 1 or house > 4 then return nil, "not_a_head" end
  if not api.is_admin(sid) and not M.is_head(api, sid, house) then return nil, "not_allowed" end
  local by_source, contributors = {}, {}
  for _, e in ipairs(School.list_ledger(500)) do
    if tonumber(e.house) == house then
      local src = tostring(e.source or "")
      by_source[src] = (by_source[src] or 0) + (tonumber(e.delta) or 0)
    end
  end
  local online = 0
  for _, s in ipairs(api.sids()) do
    if api.house(s) == house then online = online + 1 end
  end
  local counts = require("character_profile").load_counts()
  return { house = house, total = api.state.totals[house] or 0, members = counts[house] or 0, online = online, by_source = by_source,
           quests = Quests.payload(api.state.quests, api.state.quest_defs) }
end

return M
