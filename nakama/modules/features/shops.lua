-- The village shops: each sells its own goods for coins (the items' price and shop,
-- from resources/items, exported to generated/items.lua) and the apothecary buys herbs
-- (sell_price, paid as earned coins under the daily cap). Buying and selling happen
-- standing in that shop, while the village is open: by the school rules
-- (`village_open`: "always", or "weekends" for Saturday and Sunday in school time);
-- staff may shop any day. Brooms need a flying licence. Nothing sold buys a spell or
-- house points; these are cosmetics, decorations, seeds, ingredients and treats.

local Timetable = require("timetable")
local Flying = require("features.flying")

local M = { name = "shops" }

function M.open(api)
  if api.rules.village_open == "always" then return true end
  local wd = Timetable.weekday(api.school_day())
  return wd == 5 or wd == 6
end

-- Everything sold, by shop: { [shop] = { { id, price } } } and what the apothecary buys.
function M.catalogue(api)
  local shops, buys = {}, {}
  for id, def in pairs(api.ITEMS) do
    if (def.price or 0) > 0 and (def.shop or "") ~= "" then
      shops[def.shop] = shops[def.shop] or {}
      table.insert(shops[def.shop], { id = id, price = def.price })
    end
    if (def.sell_price or 0) > 0 and (def.shop or "") ~= "" then
      buys[def.shop] = buys[def.shop] or {}
      table.insert(buys[def.shop], { id = id, price = def.sell_price })
    end
  end
  for _, list in pairs(shops) do table.sort(list, function(a, b) return a.price < b.price end) end
  return shops, buys
end

function M.join(api, sid)
  local shops, buys = M.catalogue(api)
  api.push("shops", { shops = shops, buys = buys, open = M.open(api) }, sid)
end

M.requests = {}

-- {item}: buy one in the shop you stand in.
M.requests.shop_buy = function(api, sid, payload)
  local id = tostring(payload.item or "")
  local def = api.ITEMS[id]
  if not def or (def.price or 0) <= 0 then return nil, "not_for_sale" end
  if api.area(sid) ~= def.shop then return nil, "wrong_shop" end
  if not M.open(api) and not api.is_staff(sid) then return nil, "village_closed" end
  if id == "broom" and not Flying.licensed(api, sid) then return nil, "no_licence" end
  local held = api.count_item(sid, id)
  if held >= (def.max_stack or 1) then return nil, "already_owned" end
  local ok, balance, why = api.spend(sid, def.price, id)
  if not ok then return nil, why or "insufficient" end
  local fail = api.give_item(sid, id)
  if fail then
    api.nk.logger_warn(string.format("shop: %s paid for %s but it could not be given (%s)", api.name(sid), id, fail))
  end
  return { item = id, coins = balance }
end

-- {item}: sell one to the shop you stand in (herbs to the apothecary).
M.requests.shop_sell = function(api, sid, payload)
  local id = tostring(payload.item or "")
  local def = api.ITEMS[id]
  if not def or (def.sell_price or 0) <= 0 then return nil, "not_bought" end
  if api.area(sid) ~= def.shop then return nil, "wrong_shop" end
  if not M.open(api) and not api.is_staff(sid) then return nil, "village_closed" end
  if not api.take_item(sid, id, 1) then return nil, "not_owned" end
  local paid = api.pay(sid, def.sell_price, "sale", id)
  return { item = id, paid = paid }
end

return M
