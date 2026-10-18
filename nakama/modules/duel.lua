-- Duels: the only way spells touch another player, and only in a controlled setting.
-- One player challenges another by name; the duel starts when the other accepts and
-- both stand in a duelling area (school_rules.json duel_areas); a short countdown
-- (both bow), then hits between the two count: the caster's client reports a hit,
-- the server checks the duel is fighting, both are still in a duelling area, the
-- target is the opponent, the caster knows the spell and is not hitting faster than
-- a spell allows. First to `hits_to_win` wins. Nothing persists but the win/loss count;
-- leaving the area or the game forfeits. Pure helpers; the world match sends.

local M = {}

M.COUNTDOWN = 3
-- Rule sets a challenger (or a refereeing professor) picks: hits to win.
M.RULES = { three = 3, one = 1, five = 5 }
M.CHALLENGE_SECONDS = 60
M.HIT_GAP = 0.6

function M.new(a_sid, b_sid, now, rules)
  local r = M.RULES[rules or ""] and rules or "three"
  return { a = a_sid, b = b_sid, state = "challenged", hits = { [a_sid] = 0, [b_sid] = 0 }, at = now, last_hit = {}, rules = r, to_win = M.RULES[r] }
end

function M.opponent(duel, sid)
  if duel.a == sid then return duel.b end
  if duel.b == sid then return duel.a end
  return nil
end

function M.accept(duel, now)
  duel.state = "countdown"
  duel.starts_at = now + M.COUNTDOWN
end

-- Moves a duel along in time: challenges expire, countdowns turn into fights.
-- Returns true when the state changed.
function M.tick(duel, now)
  if duel.state == "challenged" and now - duel.at > M.CHALLENGE_SECONDS then
    duel.state = "over"
    duel.expired = true
    return true
  end
  if duel.state == "countdown" and now >= duel.starts_at then
    duel.state = "fighting"
    return true
  end
  return false
end

-- A reported hit from `attacker` on `target`. Returns the winner's sid when this hit
-- won the duel, true when it counted, or nil and a reason.
function M.hit(duel, attacker, target, now, hits_to_win)
  if duel.state ~= "fighting" then return nil, "not_fighting" end
  if M.opponent(duel, attacker) ~= target then return nil, "not_opponent" end
  if duel.last_hit[attacker] and now - duel.last_hit[attacker] < M.HIT_GAP then return nil, "too_fast" end
  duel.last_hit[attacker] = now
  duel.hits[attacker] = duel.hits[attacker] + 1
  if duel.hits[attacker] >= hits_to_win then
    duel.state = "over"
    duel.winner = attacker
    return attacker
  end
  return true
end

function M.forfeit(duel, loser)
  if duel.state == "over" then return end
  duel.state = "over"
  duel.winner = M.opponent(duel, loser)
  duel.forfeit = loser
end

return M
