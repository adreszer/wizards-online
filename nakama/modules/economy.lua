-- The school's currency (placeholder name "crowns" / "korony" until the owner picks one;
-- the client only knows translation keys). One unit, no denominations.
--
-- Balances live in Nakama's wallet (one per account, changeset { coins = n }), so a
-- change is atomic, can never go below zero, and lands in Nakama's wallet ledger with
-- its metadata: { source, reason, by, by_name, subject, area }. Sources:
--   lesson    attending a lesson to its end (school_rules: coins_per_lesson)
--   mystery   solving a mystery for the first time (on_solved.coins, else coins_per_mystery)
--   admin     granted or taken by an admin (RPC admin_grant_coins) or a dev cheat
--   shop      spent in the village (spend)
-- Earned coins (lesson, mystery) count toward a daily cap (max_daily_coins per school
-- day); admin grants and spending do not. Rules come from nakama/content/school_rules.json.
--
-- Storage: economy/daily (per user, server-owned): { day, earned }.
-- Coins are never bought with points or spells, and never buy them (roadmap: economy).

local nk = require("nakama")

local M = {}

M.CURRENCY = "coins"
M.DAILY_COLLECTION, M.DAILY_KEY = "economy", "daily"
M.EARNED_SOURCES = { lesson = true, mystery = true }
M.SOURCES = { lesson = true, mystery = true, admin = true, shop = true }
M.MAX_LEDGER = 100

local function wallet_of(account)
  local w = account and account.wallet
  if type(w) == "string" then
    local ok, decoded = pcall(nk.json_decode, w)
    w = ok and decoded or nil
  end
  return type(w) == "table" and w or {}
end

-- Current balance (0 for a new account or when the account cannot be read).
function M.balance(uid)
  local ok, account = pcall(nk.account_get_id, uid)
  if not ok then
    return 0
  end
  return math.floor(tonumber(wallet_of(account)[M.CURRENCY]) or 0)
end

local function clean_meta(meta)
  local out = {}
  for _, k in ipairs({ "source", "reason", "by", "by_name", "subject", "area" }) do
    if type(meta[k]) == "string" and meta[k] ~= "" then
      out[k] = meta[k]:sub(1, 120)
    end
  end
  return out
end

-- Applies `delta` (any sign) with ledger metadata. Returns ok, new balance, reason
-- ("bad_amount", "bad_source", "insufficient", "storage").
function M.change(uid, delta, meta)
  meta = meta or {}
  if type(delta) ~= "number" or delta ~= math.floor(delta) or delta == 0 then
    return false, M.balance(uid), "bad_amount"
  end
  if not M.SOURCES[meta.source] then
    return false, M.balance(uid), "bad_source"
  end
  local before = M.balance(uid)
  if before + delta < 0 then
    return false, before, "insufficient"
  end
  local ok, updated = pcall(nk.wallet_update, uid, { [M.CURRENCY] = delta }, clean_meta(meta), true)
  if not ok then
    -- Nakama refuses a change that would take the wallet below zero (a race with another change).
    nk.logger_warn(string.format("economy: wallet update %+d for %s failed: %s", delta, uid, tostring(updated)))
    return false, M.balance(uid), (before + delta < 0) and "insufficient" or "storage"
  end
  local balance = type(updated) == "table" and tonumber(updated[M.CURRENCY]) or (before + delta)
  return true, math.floor(balance), nil
end

function M.load_daily(uid)
  local ok, objects = pcall(nk.storage_read, { { collection = M.DAILY_COLLECTION, key = M.DAILY_KEY, user_id = uid } })
  if ok and objects and objects[1] and type(objects[1].value) == "table" then
    return { day = tonumber(objects[1].value.day) or -1, earned = tonumber(objects[1].value.earned) or 0 }
  end
  return { day = -1, earned = 0 }
end

local function save_daily(uid, daily)
  pcall(nk.storage_write, {
    { collection = M.DAILY_COLLECTION, key = M.DAILY_KEY, user_id = uid, value = daily, permission_read = 1, permission_write = 0 },
  })
end

-- How much of `amount` may still be earned today under `cap` (pure: for tests and callers).
function M.allowance(daily, day, amount, cap)
  local earned = (daily.day == day) and daily.earned or 0
  return math.max(0, math.min(amount, cap - earned))
end

-- Pays earned coins (lesson, mystery), capped per school day. Returns paid, balance, reason
-- (paid may be less than amount, or 0 with reason "daily_cap").
function M.earn(uid, amount, meta, rules, day)
  if not M.EARNED_SOURCES[meta and meta.source] then
    return 0, M.balance(uid), "bad_source"
  end
  local daily = M.load_daily(uid)
  local pay = M.allowance(daily, day, math.floor(amount or 0), rules.max_daily_coins)
  if pay <= 0 then
    return 0, M.balance(uid), "daily_cap"
  end
  local ok, balance, reason = M.change(uid, pay, meta)
  if not ok then
    return 0, balance, reason
  end
  save_daily(uid, { day = day, earned = ((daily.day == day) and daily.earned or 0) + pay })
  return pay, balance, nil
end

-- Takes coins for a purchase. Returns ok, balance, reason ("insufficient"…).
function M.spend(uid, amount, reason, meta)
  meta = meta or {}
  meta.source, meta.reason = "shop", reason
  if type(amount) ~= "number" or amount <= 0 or amount ~= math.floor(amount) then
    return false, M.balance(uid), "bad_amount"
  end
  return M.change(uid, -amount, meta)
end

-- Empties the purse and forgets today's earnings (admin tooling and tests). Returns the balance (0).
function M.reset(uid, by_name)
  local balance = M.balance(uid)
  if balance > 0 then
    M.change(uid, -balance, { source = "admin", reason = "reset", by_name = by_name or "" })
  end
  pcall(nk.storage_delete, { { collection = M.DAILY_COLLECTION, key = M.DAILY_KEY, user_id = uid } })
  return M.balance(uid)
end

-- The newest ledger entries: [{ delta, balance?, source, reason, by_name, subject, area, at }].
function M.ledger(uid, limit)
  limit = math.max(1, math.min(tonumber(limit) or 50, M.MAX_LEDGER))
  local ok, items = pcall(nk.wallet_ledger_list, uid, limit)
  local out = {}
  if not ok or type(items) ~= "table" then
    return out
  end
  for _, item in ipairs(items) do
    local meta = type(item.metadata) == "table" and item.metadata or {}
    local changes = type(item.changeset) == "table" and item.changeset or {}
    table.insert(out, { delta = tonumber(changes[M.CURRENCY]) or 0, source = meta.source or "", reason = meta.reason or "",
                        by_name = meta.by_name or "", subject = meta.subject or "", area = meta.area or "",
                        at = item.create_time or 0 })
  end
  return out
end

return M
