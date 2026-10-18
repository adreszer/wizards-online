-- Parlour games: Star Stones (Gwiezdne Kamienie), the common-room board game. Two
-- players in the same room: one invites the other by name, the other accepts; they take
-- turns dropping a stone into one of seven columns of a six-row frame; four of one's
-- stones in a line (across, up or slanting) win, a full frame is a draw. The server keeps
-- the board and checks every move; players and onlookers in the room see the game.
-- Leaving the room or the game forfeits. Results count toward each player's record and
-- the Unfinished Wing's shared progress.
--
-- Memory only: state.features.games[id] = { id, a, b, names, board[1..42], turn, winner, draw, area, at }
-- Push "game": the game view (to both players and onlookers in the room), {} when it is gone.

local Store = require("store")
local Wing = require("features.wing")

local M = { name = "games" }

M.COLS, M.ROWS = 7, 6
M.INVITE_SECONDS = 60
M.STATS_COLLECTION, M.STATS_KEY = "social", "game_stats"

local function games(api)
  local f = api.state.features
  f.games = f.games or {}
  f.game_of = f.game_of or {}
  return f.games, f.game_of
end

-- Index of (col, row), both 1-based, row 1 at the bottom.
local function idx(col, row) return (row - 1) * M.COLS + col end

-- The row a stone dropped into `col` lands in, or nil when the column is full.
function M.drop_row(board, col)
  for row = 1, M.ROWS do
    if board[idx(col, row)] == 0 then return row end
  end
  return nil
end

-- Whether the stone at (col, row) completes four in a line.
function M.wins(board, col, row)
  local who = board[idx(col, row)]
  if who == 0 then return false end
  for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
    local n = 1
    for _, s in ipairs({ 1, -1 }) do
      local c, r = col + d[1] * s, row + d[2] * s
      while c >= 1 and c <= M.COLS and r >= 1 and r <= M.ROWS and board[idx(c, r)] == who do
        n = n + 1
        c, r = c + d[1] * s, r + d[2] * s
      end
    end
    if n >= 4 then return true end
  end
  return false
end

function M.new_board()
  local b = {}
  for i = 1, M.COLS * M.ROWS do b[i] = 0 end
  return b
end

local function view(api, g)
  return { id = g.id, state = g.state, a = g.names[1], b = g.names[2], board = g.board, turn = g.turn, winner = g.winner or 0,
           draw = g.draw == true, area = g.area, cols = M.COLS, rows = M.ROWS }
end

local function send(api, g)
  local sids = {}
  for _, pl in ipairs(api.players_in(g.area)) do table.insert(sids, pl.sid) end
  for _, s in ipairs({ g.a, g.b }) do
    if api.area(s) ~= g.area then table.insert(sids, s) end
  end
  api.push("game", view(api, g), sids)
end

local function record(api, sid, result)
  local uid = api.uid(sid)
  if not uid then return end
  local s = Store.read(M.STATS_COLLECTION, M.STATS_KEY, uid) or {}
  s[result] = (tonumber(s[result]) or 0) + 1
  Store.write(M.STATS_COLLECTION, M.STATS_KEY, uid, s, true)
end

-- Wins/draws/losses of `uid` (profile cards).
function M.stats(uid)
  local s = Store.read(M.STATS_COLLECTION, M.STATS_KEY, uid) or {}
  return { wins = tonumber(s.win) or 0, draws = tonumber(s.draw) or 0, losses = tonumber(s.loss) or 0 }
end

local function finish(api, g)
  local all, of = games(api)
  if g.state == "playing" then
    if g.draw then
      record(api, g.a, "draw")
      record(api, g.b, "draw")
    elseif g.winner > 0 then
      record(api, g.winner == 1 and g.a or g.b, "win")
      record(api, g.winner == 1 and g.b or g.a, "loss")
    end
    Wing.contribute(api, 2)
  end
  g.state = "over"
  send(api, g)
  all[g.id] = nil
  if of[g.a] == g.id then of[g.a] = nil end
  if of[g.b] == g.id then of[g.b] = nil end
end

function M.leave(api, sid)
  local all, of = games(api)
  local g = of[sid] and all[of[sid]]
  if g then
    if g.state == "playing" then g.winner = (sid == g.a) and 2 or 1 end
    finish(api, g)
  end
end

function M.area(api, sid, area, previous)
  local all, of = games(api)
  local g = of[sid] and all[of[sid]]
  if g and area ~= g.area then
    if g.state == "playing" then g.winner = (sid == g.a) and 2 or 1 end
    finish(api, g)
  end
end

function M.tick(api, now)
  local all = games(api)
  for _, g in pairs(all) do
    if g.state == "invited" and now - g.at > M.INVITE_SECONDS then finish(api, g) end
  end
end

M.requests = {}

-- {name}: invite someone in the same room.
M.requests.game_invite = function(api, sid, payload)
  local all, of = games(api)
  if of[sid] then return nil, "already_playing" end
  local target = type(payload.name) == "string" and api.find(payload.name) or nil
  if not target then return nil, "no_such_player" end
  if target == sid then return nil, "not_yourself" end
  if of[target] then return nil, "busy" end
  local area = api.area(sid)
  if area == "" or api.area(target) ~= area then return nil, "not_together" end
  api.state.features.game_seq = (api.state.features.game_seq or 0) + 1
  local g = { id = api.state.features.game_seq, a = sid, b = target, names = { api.name(sid), api.name(target) }, board = M.new_board(),
              turn = 1, state = "invited", area = area, at = api.now }
  all[g.id], of[sid], of[target] = g, g.id, g.id
  api.notice(target, "GAME_INVITED", { api.name(sid) }, 10)
  send(api, g)
  return { id = g.id }
end

-- {accept = bool}: the invited player answers.
M.requests.game_answer = function(api, sid, payload)
  local all, of = games(api)
  local g = of[sid] and all[of[sid]]
  if not g or g.state ~= "invited" or g.b ~= sid then return nil, "no_invite" end
  if payload.accept ~= true then
    finish(api, g)
    return { accepted = false }
  end
  g.state = "playing"
  send(api, g)
  return { accepted = true }
end

-- {col}: the player whose turn it is drops a stone.
M.requests.game_move = function(api, sid, payload)
  local all, of = games(api)
  local g = of[sid] and all[of[sid]]
  if not g or g.state ~= "playing" then return nil, "no_game" end
  local me = (sid == g.a) and 1 or 2
  if g.turn ~= me then return nil, "not_your_turn" end
  local col = math.floor(tonumber(payload.col) or 0)
  if col < 1 or col > M.COLS then return nil, "bad_move" end
  local row = M.drop_row(g.board, col)
  if not row then return nil, "column_full" end
  g.board[idx(col, row)] = me
  if M.wins(g.board, col, row) then
    g.winner = me
  else
    local full = true
    for c = 1, M.COLS do
      if M.drop_row(g.board, c) then full = false end
    end
    g.draw = full
  end
  g.turn = 3 - me
  if g.winner or g.draw then
    finish(api, g)
  else
    send(api, g)
  end
  return { col = col, row = row }
end

M.requests.game_resign = function(api, sid, payload)
  local all, of = games(api)
  local g = of[sid] and all[of[sid]]
  if not g then return nil, "no_game" end
  if g.state == "playing" then g.winner = (sid == g.a) and 2 or 1 end
  finish(api, g)
  return {}
end

return M
