-- Movement sanity: clients report their own positions (OP_STATE), so the server checks that
-- each one is reachable from the last accepted one. A state that is not is neither relayed
-- nor kept as the player's position, counts a strike, and enough strikes in a window send
-- the client back to the last accepted position (OP_PUSH kind "position") and file one
-- moderation report (from "server") that admins see in the reports list.
--
-- Lenient on purpose: lag bunches states up, a moving stair carries the body, and a respawn
-- (checkpoint), a seat or a house change teleports it, places the server does not know of.
-- So every jump gets MAX_SPEED x elapsed + SLACK, and one jump of any length is forgiven
-- every TELEPORT_COOLDOWN seconds.
local M = {}

-- The fastest legitimate body (characters/player/player_movement.gd): a boosted broom does
-- fly_boost_speed 30 m/s plus fly_vertical_speed 8 (~31 m/s), a free fall caps at
-- max_fall_speed 40; running is 7.5. Some headroom on top.
M.MAX_SPEED = 45.0
M.SLACK = 8.0               -- metres on every check: jitter, stair carry, a seat snap
M.MAX_ELAPSED = 5.0         -- a long silence earns at most this many seconds of travel
M.TELEPORT_COOLDOWN = 20.0  -- one free jump (respawn, spawn, house change) this often
M.STRIKE_WINDOW = 30.0      -- strikes older than this are forgotten
M.STRIKES_TO_CORRECT = 3    -- this many in the window: snap the client back, report once
M.CORRECTION_GRACE = 2.0    -- after a snap, states still in flight from the far place are dropped quietly

local function distance(a, b)
  local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- A fresh tracker for one session.
function M.new()
  return { pos = nil, at = 0, strikes = {}, teleport_at = -math.huge, corrected_at = -math.huge, reported_at = -math.huge }
end

-- Checks the reported position `pos` ({x,y,z}) at server time `now` against tracker `t`.
-- Returns verdict, info: "accept" (relay it; info.teleport when it used the free jump),
-- "drop" (stale after a correction: not relayed, no strike), "reject" (a strike; info.correct
-- when the client should be snapped back to t.pos, info.report when it is time to file one).
function M.check(t, pos, now)
  if not t.pos then
    t.pos, t.at = pos, now
    return "accept", {}
  end
  local moved = distance(pos, t.pos)
  local elapsed = math.min(math.max(now - t.at, 0), M.MAX_ELAPSED)
  local allowed = M.MAX_SPEED * elapsed + M.SLACK
  if moved <= allowed then
    t.pos, t.at = pos, now
    return "accept", { moved = moved }
  end
  if now - t.corrected_at < M.CORRECTION_GRACE then
    return "drop", { moved = moved }
  end
  if now - t.teleport_at >= M.TELEPORT_COOLDOWN then
    t.teleport_at = now
    t.pos, t.at = pos, now
    return "accept", { moved = moved, teleport = true }
  end
  -- A strike: the old position stays (and its time, so a real catch-up later still fits).
  local kept = {}
  for _, at in ipairs(t.strikes) do
    if now - at < M.STRIKE_WINDOW then table.insert(kept, at) end
  end
  table.insert(kept, now)
  t.strikes = kept
  local info = { moved = moved, allowed = allowed, strikes = #kept }
  if #kept >= M.STRIKES_TO_CORRECT then
    info.correct = true
    t.corrected_at = now
    t.at = now
    t.strikes = {}
    if now - t.reported_at >= M.STRIKE_WINDOW then
      t.reported_at = now
      info.report = true
    end
  end
  return "reject", info
end

return M
