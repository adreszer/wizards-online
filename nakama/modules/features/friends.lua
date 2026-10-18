-- Friends: ask someone by name (online or not, as long as they have played), they
-- accept or decline; either can remove the other later. Friends see each other online
-- in the friends list (and where: the area, only between friends). Direct messages
-- themselves stay in chat.lua; the client shows them arriving as paper birds.
--
-- Storage: social/friends per user (server-only): { friends = { [uid] = name }, incoming = { [uid] = name }, outgoing = { [uid] = name } }
-- Push "friends": { friends = [ { name, online, area } ], incoming = [names], outgoing = [names] }

local Store = require("store")
local Chat = require("chat")

local M = { name = "friends" }

M.COLLECTION, M.KEY = "social", "friends"
M.MAX = 100

local function load(uid)
  local r = Store.read(M.COLLECTION, M.KEY, uid) or {}
  for _, k in ipairs({ "friends", "incoming", "outgoing" }) do
    r[k] = type(r[k]) == "table" and r[k] or {}
  end
  return r
end

local function save(uid, rec) Store.write(M.COLLECTION, M.KEY, uid, rec) end

local function names(t)
  local out = {}
  for _, n in pairs(t) do table.insert(out, n) end
  table.sort(out)
  return out
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function M.view(api, rec)
  local list = {}
  for uid, name in pairs(rec.friends) do
    local sid = api.sid_of_user(uid)
    table.insert(list, { name = sid and api.name(sid) or name, online = sid ~= nil, area = sid and api.area(sid) or "" })
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  return { friends = list, incoming = names(rec.incoming), outgoing = names(rec.outgoing) }
end

-- Sends the list to `uid` if they are online.
local function send_uid(api, uid)
  local sid = api.sid_of_user(uid)
  if sid then api.push("friends", M.view(api, load(uid)), sid) end
end

function M.join(api, sid)
  local uid = api.uid(sid)
  local rec = load(uid)
  api.push("friends", M.view(api, rec), sid)
  for fuid, _ in pairs(rec.friends) do send_uid(api, fuid) end
end

function M.leave(api, sid)
  -- The leaving player is still in the match while hooks run: show them offline.
  local uid, my_name = api.uid(sid), api.name(sid)
  for fuid, _ in pairs(load(uid).friends) do
    local fsid = api.sid_of_user(fuid)
    if fsid then
      local view = M.view(api, load(fuid))
      for _, f in ipairs(view.friends) do
        if f.name == my_name then f.online, f.area = false, "" end
      end
      api.push("friends", view, fsid)
    end
  end
end

-- The other side of a request by display name: uid and the name to show.
local function target(api, name)
  if type(name) ~= "string" or name == "" then return nil end
  local sid = api.find(name)
  if sid then return api.uid(sid), api.name(sid) end
  local uid = Chat.uid_for_name(name)
  if uid then return uid, name end
  return nil
end

M.requests = {}

M.requests.friend_add = function(api, sid, payload)
  local me = api.uid(sid)
  local uid, name = target(api, payload.name)
  if not uid then return nil, "no_such_player" end
  if uid == me then return nil, "not_yourself" end
  local mine, theirs = load(me), load(uid)
  if mine.friends[uid] then return nil, "already_friends" end
  if count(mine.friends) >= M.MAX then return nil, "too_many" end
  if mine.incoming[uid] then
    -- They asked first: this is an accept.
    mine.incoming[uid], theirs.outgoing[me] = nil, nil
    mine.friends[uid], theirs.friends[me] = name, api.name(sid)
  else
    mine.outgoing[uid], theirs.incoming[me] = name, api.name(sid)
    local tsid = api.sid_of_user(uid)
    if tsid then api.notice(tsid, "FRIEND_ASKED", { api.name(sid) }, 8) end
  end
  save(me, mine)
  save(uid, theirs)
  api.push("friends", M.view(api, mine), sid)
  send_uid(api, uid)
  return { name = name, friends = mine.friends[uid] ~= nil }
end

M.requests.friend_accept = function(api, sid, payload)
  local me = api.uid(sid)
  local mine = load(me)
  local uid
  for u, n in pairs(mine.incoming) do
    if n == payload.name then uid = u end
  end
  if not uid then return nil, "no_request" end
  return M.requests.friend_add(api, sid, { name = mine.incoming[uid] })
end

-- {name}: removes a friend, or withdraws or declines a request.
M.requests.friend_remove = function(api, sid, payload)
  local me = api.uid(sid)
  local mine = load(me)
  local uid
  for _, t in ipairs({ mine.friends, mine.incoming, mine.outgoing }) do
    for u, n in pairs(t) do
      if n == payload.name then uid = u end
    end
  end
  if not uid then return nil, "not_friends" end
  local theirs = load(uid)
  mine.friends[uid], mine.incoming[uid], mine.outgoing[uid] = nil, nil, nil
  theirs.friends[me], theirs.incoming[me], theirs.outgoing[me] = nil, nil, nil
  save(me, mine)
  save(uid, theirs)
  api.push("friends", M.view(api, mine), sid)
  send_uid(api, uid)
  return {}
end

-- Whether two users are friends (other modules: profile cards).
function M.are_friends(uid_a, uid_b)
  return load(uid_a).friends[uid_b] ~= nil
end

return M
