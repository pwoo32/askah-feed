-- Deals.lua
-- A window that pops up when you open the auction house and lists ways to
-- make money there, worked out from AskAH's own scans:
--   * Sure profit: listings below the vendor sell price (buy, sell to a vendor)
--   * Cheap vs the usual price: listings at 70% or less of what the item
--     usually goes for, after 3+ scans (common flipping rule; TSM-style)
--   * Price gaps: a few listings far under the next cheapest ones
--   * Crafting profit: your known recipes whose result sells for more than
--     the materials cost here
--   * Cheaper here than at the other AH (faction vs neutral)
--   * Crazy prices: items listed far above usual (sell yours now)
-- Profit is counted after the AH cut (faction 5%, neutral 15%) and a deposit
-- estimate, and every deal must clear a minimum profit.
-- Relist deals (cheap, gaps, crafting, cross-AH) are priced at what you could
-- really relist at and shown only when that relist sells (Sellable below).
local _, ns = ...
local D = {}
ns.Deals = D

local GREEN, RED, YELLOW, GREY, BLUE, ORANGE = "|cff33ff33", "|cffff4040", "|cffffd200", "|cff999999", "|cff33ccff", "|cffff8040"
local GII = function(x) local B = AskAHBlizzAPI; if B and B.GetItemInfo then return B.GetItemInfo(x) end return ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(x) end -- Blizzard API data first, then the game

local CUT = { faction = 0.95, neutral = 0.85 }
local DEPOSIT = { faction = 0.05, neutral = 0.15 } -- share of the vendor price, per 12h listing (estimate)
local SNIPE_AT = 0.70      -- buy at 70% of the usual price or less
local MIN_SEEN = 3         -- scans before the usual price is trusted
local MIN_PROFIT = 20 * 100 -- 20 silver
local MIN_MARGIN = 1.15    -- at least 15% over what you pay
local GAP_AT = 0.70        -- cheapest listings at 70% or less of the next ones
local CRAZY_AT = 2.0       -- listed at twice the usual price
local MAX_ROWS = 12        -- per section
local DEALS_V = 2          -- saved deal lists from before this are worked out again
-- Will the relist sell? A deal is only shown when, at the price you'd relist at:
local MIN_SPD = 1          -- it sells at least once a day at that AH (measured)
local MIN_CHANCE = 0.5     -- each listing has 50%+ chance to sell before it runs out
local SELL_DAYS = 1        -- buy only what the whole AH sells in about a day (you're cheapest only
                           -- until the next undercut, so more than that sits)
-- Forever's Black Market vendor (Mister Graphed) sells these at a fixed 50g.
local BLACK_MARKET = { [13468] = 50 * 10000, [12363] = 50 * 10000 }

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h, i, j, k = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h, i, j, k end
end

local function Money(c) return ns.Data.Money(c) end

local function Vendor(itemID)
  local sell = select(11, try(GII, itemID))
  return (type(sell) == "number" and sell > 0) and sell or nil
end

local function NameOf(itemID, e)
  return (e and e.n) or (try(GII, itemID)) or ("item " .. itemID)
end

local function DB()
  AskAHDB.deals = AskAHDB.deals or {}
  return AskAHDB.deals
end

local function Owned()
  local c = ns.Data.Char()
  local own = {}
  for id, e in pairs(c.bags or {}) do own[id] = (own[id] or 0) + (e.c or 0) end
  for id, e in pairs(c.bank or {}) do own[id] = (own[id] or 0) + (e.c or 0) end
  return own
end

-------------------------------------------------------------------------------
-- Checks that need every listing of an item. Run for every item at the end of
-- each full scan, and again for single items whenever you search the AH
-- yourself (so deals that were bought drop off and prices stay current).
-- rows = sorted { {unit, count}, ... } (your own listings left out)
-- full = false when rows may be only part of the listings (then the price
-- gap check is skipped, since it needs to see the next listings too).
-------------------------------------------------------------------------------
local function CheckItem(itemID, rows, e, which, full)
  local cut, dep = CUT[which], DEPOSIT[which]
  local res = {}
  if not e or #rows == 0 then return res end
  local usual, seen = e.prevAvg, e.prevSeen or 0
  -- a "usual price" over 10x what the item lists for now was pushed up by
  -- troll listings (e.g. arrows at 8 million gold): don't trust it
  local now = e.m or e.p
  if usual and now and now > 0 and usual > 10 * now and usual > 10 * rows[1][1] then usual = nil end
  local vend = Vendor(itemID)
  local deposit = (vend or 0) * dep

  -- 1. Below the vendor price: sure profit, no AH cut.
  if vend then
    local qty, profit, top = 0, 0, 0
    for _, r in ipairs(rows) do
      if r[1] >= vend then break end
      qty, profit, top = qty + r[2], profit + (vend - r[1]) * r[2], r[1]
    end
    if profit >= 5 * 100 then
      res.vendor = { id = itemID, n = NameOf(itemID, e), qty = qty, buy = rows[1][1],
        upto = top, sell = vend, profit = profit }
    end
  end

  -- 2. Cheap compared with the usual price (needs history).
  -- What you can really relist at: just under the cheapest listing you leave
  -- up, and never over the usual price. The usual price is an average, so it
  -- lags when prices are falling (new servers deflate for weeks): it is also
  -- capped at the recent average (e.avg moves faster than e.prevAvg).
  -- Before this, deals counted on selling at the old average while the AH
  -- was full of cheaper listings, and those relists never sold.
  if usual and seen >= MIN_SEEN then
    local flooded = e.q and e.qa and e.q >= 3 * e.qa and e.m and e.m < usual * 0.8
    local cap = math.min(usual, e.avg or usual)
    if not flooded then
      -- the Blizzard feed sends only the cheapest dozen listings: past the
      -- last one we see, the next price is unknown but at least that much
      -- (and the market price, where a quarter of the units are listed)
      local visible = 0
      for _, r in ipairs(rows) do visible = visible + r[2] end
      local cut_off = visible < (e.q or 0)
      local qty, cost, best = 0, 0, nil
      for i, r in ipairs(rows) do
        if r[1] > usual * SNIPE_AT then break end
        qty, cost = qty + r[2], cost + r[1] * r[2]
        local nextUp = rows[i + 1] and rows[i + 1][1]
        if not nextUp and cut_off then nextUp = math.max(r[1], e.m or 0) end
        local sellAt = nextUp and math.min(cap, nextUp * 0.99) or cap
        local net = sellAt * cut - deposit
        local profit = net * qty - cost
        if net >= r[1] * MIN_MARGIN and profit >= MIN_PROFIT and (not best or profit > best.profit) then
          best = { qty = qty, cost = cost, upto = r[1], sell = sellAt, profit = profit }
        end
      end
      if best then
        res.snipe = { id = itemID, n = NameOf(itemID, e), qty = best.qty, cost = best.cost, buy = rows[1][1], upto = best.upto,
          sell = best.sell, usual = usual, profit = best.profit, pct = math.floor(rows[1][1] / usual * 100 + 0.5), seen = seen,
          thin = (e.qa or 0) < 3 }
      end
    end
    -- 4. Crazy high: everything listed is far over the usual price.
    if full and rows[1][1] >= usual * CRAZY_AT and usual >= 10 * 100 then
      res.crazy = { id = itemID, n = NameOf(itemID, e), buy = rows[1][1], sell = usual, x = rows[1][1] / usual }
    end
  end

  -- 3. Price gap: the cheapest few are far under the next listings.
  if full and not res.snipe and #rows >= 3 then
    local low = rows[1][1]
    local qty, nextP = 0, nil
    for _, r in ipairs(rows) do
      if r[1] <= low * 1.05 then qty = qty + r[2] else nextP = r[1] break end
    end
    local after = 0
    for _, r in ipairs(rows) do if nextP and r[1] >= nextP then after = after + 1 end end
    local overpricedNext = usual and seen >= MIN_SEEN and nextP and nextP > usual * 1.3
    if nextP and after >= 2 and low <= nextP * GAP_AT and not overpricedNext then
      local sellAt = nextP * 0.99
      if usual and seen >= MIN_SEEN then sellAt = math.min(sellAt, usual, e.avg or usual) end
      local net = sellAt * cut - deposit
      local profit = (net - low) * qty
      if profit >= MIN_PROFIT and net >= low * MIN_MARGIN then
        res.gap = { id = itemID, n = NameOf(itemID, e), qty = qty, cost = low * qty, buy = low, upto = low, sell = sellAt, nextP = nextP,
          profit = profit, known = usual and seen >= MIN_SEEN }
      end
    end
  end
  return res
end

local LISTS = { "vendor", "snipe", "gap", "crazy" }
local function SortLists(out)
  local sortP = function(a, b) return a.profit > b.profit end
  table.sort(out.vendor, sortP); table.sort(out.snipe, sortP); table.sort(out.gap, sortP)
  table.sort(out.crazy, function(a, b) return a.x > b.x end)
end

-- t, src: when the listings are from and where ("feed" = Blizzard's hourly
-- data, see Feed.lua); a full scan in game passes neither.
function D.FromScan(scanned, key, neutral, t, src)
  local which = neutral and "neutral" or "faction"
  local prices = ns.Data.Prices(which)
  local out = { v = DEALS_V, t = t or time(), src = src, which = which, vendor = {}, snipe = {}, gap = {}, crazy = {}, scans = 0 }
  local trusted = 0
  for itemID, rows in pairs(scanned) do
    local e = prices[itemID]
    if e and #rows > 0 then
      if (e.prevSeen or 0) >= MIN_SEEN then trusted = trusted + 1 end
      local res = CheckItem(itemID, rows, e, which, true)
      for _, l in ipairs(LISTS) do if res[l] then out[l][#out[l] + 1] = res[l] end end
    end
  end
  out.trusted = trusted
  SortLists(out)
  DB()[key] = out
  D.Refresh()
end

-- Listings you can see right now (your own AH searches, buying, the page
-- after a purchase): seen[itemID] = { {unit, count}, ... }. complete = true
-- when that is every listing of those items. Deals for these items are
-- worked out again: gone ones drop off, changed ones get today's numbers.
local lastClicked -- { id =, t = } the deal you clicked to search for
function D.OnLive(seen, complete)
  local key = ns.Data.CurrentKey()
  local d = DB()[key]
  if not d then return end
  -- the deal you clicked has no listings left at all
  if complete and lastClicked and time() - lastClicked.t < 30 and not seen[lastClicked.id] then
    seen[lastClicked.id] = {}
  end
  local prices = ns.Data.Prices(d.which)
  local changed = false
  for id, rows in pairs(seen) do
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    local res = CheckItem(id, rows, prices[id], d.which, complete)
    for _, l in ipairs(LISTS) do
      local list, at = d[l], nil
      for i, r in ipairs(list) do if r.id == id then at = i break end end
      local new = res[l]
      if new then
        new.live = time()
        if at then list[at] = new else list[#list + 1] = new end
        changed = true
      elseif at and complete then
        table.remove(list, at); changed = true
      end
    end
  end
  if changed then SortLists(d); D.QueueRefresh() end
end

-------------------------------------------------------------------------------
-- Checks that work from saved prices: run each time the window is drawn.
-------------------------------------------------------------------------------
local function Fresh(e, hours) return e and e.t and (time() - e.t) < hours * 3600 end
local function Market(e) return e.m or e.p end

-- Will it sell? From listings that vanish between scans (Data.lua SoldSince).
local function Rate(itemID, which)
  local e = ns.Data.Prices(which)[itemID]
  if e and e.spdN and e.spdN >= 1 and e.spd then return e.spd, e.spdN, e end
  return nil, 0, e
end
D.Rate = Rate
local function RateText(spd, n)
  if not spd then return "sell rate not measured yet" end
  local word
  if spd >= 5 then word = "sells fast" elseif spd >= 1 then word = "sells" elseif spd >= 0.2 then word = "sells slowly"
  else word = "barely sells" end
  return ("%s ~%s/day%s"):format(word, spd >= 10 and ("%d"):format(spd) or ("%.1f"):format(spd), n < 2 and "?" or "")
end
-- Your own record with the item (Sales.lua): sold vs came back unsold, last 30 days.
local ownCache, ownT = nil, 0
local function OwnRecord(itemID)
  if not (ns.Sales and ns.Sales.List) then return nil end
  if not ownCache or time() - ownT > 10 then
    ownCache, ownT = {}, time()
    local ok, list = pcall(ns.Sales.List)
    if ok and type(list) == "table" then
      local since = time() - 30 * 86400
      for _, e in ipairs(list) do
        if e.id and (e.t or 0) >= since then
          local o = ownCache[e.id] or { sold = 0, unsold = 0 }
          ownCache[e.id] = o
          if e.kind then o.unsold = o.unsold + (e.q or 1) else o.sold = o.sold + (e.q or 1) end
        end
      end
    end
  end
  return ownCache[itemID]
end
local function OwnText(itemID)
  local o = OwnRecord(itemID)
  if not o then return nil end
  return ("Your auctions (30 days): %d sold, %d didn't sell"):format(o.sold, o.unsold)
end
D.OwnText = OwnText

-- Where to post it: compare faction and neutral by what you'd get per item
-- after the cut, but only at an AH where it actually sells (1+ a day), and
-- how long the stack would take to sell.
local function WhereToSell(itemID, qty, here)
  local best, info = nil, {}
  for _, w in ipairs({ "faction", "neutral" }) do
    local e = ns.Data.Prices(w)[itemID]
    if e and e.t and time() - e.t < 3 * 86400 then
      local price = math.min(e.m or e.p, e.avg or e.m or e.p)
      local net = price * CUT[w] - (Vendor(itemID) or 0) * DEPOSIT[w]
      local spd, n = Rate(itemID, w)
      -- chance one listing sells before it runs out (SellAdvice.lua)
      local chance
      if ns.Sell and ns.Sell.Advise then
        local ok, adv = pcall(ns.Sell.Advise, itemID, 1)
        chance = ok and adv and adv.ah and adv.ah[w] and adv.ah[w].chance or nil
      end
      info[w] = { net = net, spd = spd, n = n, chance = chance }
      local ok = spd and spd >= 1
      if ok and (not best or net > info[best].net) then best = w end
    end
  end
  local function label(w) return w == "neutral" and "neutral AH" or "faction AH" end
  local parts = {}
  for _, w in ipairs({ "faction", "neutral" }) do
    local i = info[w]
    if i then
      parts[#parts + 1] = ("%s: ~%s each, %s%s"):format(w == "neutral" and "Neutral" or "Faction", Money(i.net), RateText(i.spd, i.n),
        i.chance and (", " .. math.floor(i.chance * 100 + 0.5) .. "% chance to sell") or "")
    end
  end
  local text = table.concat(parts, "; ")
  if best then
    local i = info[best]
    local days = qty and qty > 0 and i.spd > 0 and qty / i.spd or 0
    text = GREEN .. "Sell at the " .. label(best) .. "|r" .. GREY .. " (" .. text .. ")" ..
      (days >= 2 and (" - about %d days to sell %d"):format(math.ceil(days), qty) or "") .. "|r"
  elseif next(info) then
    local known = false
    for _, i in pairs(info) do if i.spd and i.n >= 2 then known = true end end
    if known then text = RED .. "Won't sell well at either AH|r" .. GREY .. " (" .. text .. ")|r"
    else text = GREY .. "Not sure it sells yet (" .. text .. ")|r" end
  end
  return text, best, info
end
D.WhereToSell = WhereToSell
-- Will a relist of this deal really sell? Checked at the price you'd relist
-- at (not the usual price), at the AH you'd sell at:
--   * a measured sell rate of 1+ a day there (unknown rates are left out)
--   * 50%+ chance each listing sells before it runs out (SellAdvice.lua: the
--     feed's sell-through for listings like it, demand vs competition, and
--     your own record, checked against what really happened)
--   * your own auctions of it didn't mostly come back unsold lately
-- and how many you should buy: what sells in about SELL_DAYS days. The
-- profit becomes the expected profit (relist until sold, up to 3 times,
-- then vendor), for that many.
-- Returns ok, info = { qty, profit, chance, spd, why }.
local sellCache, sellCacheT = {}, 0
local function Sellable(id, w, sellAt, qty, cost)
  if time() - sellCacheT > 60 then sellCache, sellCacheT = {}, time() end
  local ck = id .. ":" .. w .. ":" .. math.floor(sellAt)
  local adv = sellCache[ck]
  if adv == nil then
    adv = false
    if ns.Sell and ns.Sell.Advise then
      local ok, a = pcall(ns.Sell.Advise, id, 1, false, { w = w, unit = math.max(1, math.floor(sellAt)), ahead = 0 })
      adv = ok and a and a.ah and a.ah[w] or false
    end
    sellCache[ck] = adv
  end
  local spd, n = Rate(id, w)
  local info = { spd = spd, chance = adv and adv.chance or nil }
  if not spd or n < 2 then info.why = "unknown"; return false, info end
  if spd < MIN_SPD then info.why = "slow"; return false, info end
  local o = OwnRecord(id)
  if o and o.unsold >= 3 and o.unsold > o.sold then info.why = "yours"; return false, info end
  if not adv then info.why = "unknown"; return false, info end
  if adv.chance < MIN_CHANCE then info.why = "chance"; return false, info end
  qty = qty or 1
  local buyQty = math.max(1, math.min(qty, math.floor(spd * SELL_DAYS)))
  local each = (cost or 0) / math.max(qty, 1)
  local value = adv.value or 0 -- expected gold from one listing, after cut and lost deposits
  info.qty, info.each, info.value = buyQty, each, value
  info.profit = (value - each) * buyQty
  if info.profit < MIN_PROFIT or value < each * 1.1 then info.why = "thin"; return false, info end
  return true, info
end
D.Sellable = Sellable

local WHY = {
  unknown = "no measured sell rate yet",
  slow = "sell under once a day",
  chance = "under 50% chance to sell at the relist price",
  yours = "your own auctions of them mostly came back unsold",
  thin = "too little profit once the chance to sell is counted",
}
local function Pct(p) return math.floor((p or 0) * 100 + 0.5) .. "%" end

-- Crafting: your recipes whose result sells for more than the mats cost here.
local function CraftDeals(which)
  local prices = ns.Data.Prices(which)
  local cut = CUT[which]
  local out = {}
  for prof, data in pairs(ns.Data.Char().recipes or {}) do
    for _, rec in ipairs(data.list or {}) do
      local pe = rec.o and prices[rec.o]
      if pe and Fresh(pe, 48) and (pe.seen or 0) >= 2 then
        local cost, missing = 0, {}
        for id, q in pairs(rec.r) do
          local me = prices[id]
          if me and Fresh(me, 48) then cost = cost + Market(me) * q
          else missing[#missing + 1] = NameOf(id, me) end
        end
        local made = rec.mk or 1
        local sellEach = math.min(Market(pe), pe.avg or Market(pe))
        local net = sellEach * made * cut - (Vendor(rec.o) or 0) * DEPOSIT[which] * made
        local profit = net - cost
        if #missing <= 1 and profit >= MIN_PROFIT and net >= cost * MIN_MARGIN then
          out[#out + 1] = { id = rec.o, n = rec.n, prof = prof, cost = cost, sell = sellEach * made, profit = profit,
            missing = missing[1], made = made }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.profit > b.profit end)
  return out
end

-- Cheaper here than what it sells for at the other auction house.
local function CrossDeals(which)
  local other = (which == "neutral") and "faction" or "neutral"
  local here, there = ns.Data.Prices(which), ns.Data.Prices(other)
  local cut = CUT[other]
  local out = {}
  for id, h in pairs(here) do
    local o = there[id]
    if o and Fresh(h, 12) and Fresh(o, 24) and (o.seen or 1) >= 1 then
      local sell = math.min(Market(o), o.avg or Market(o))
      local net = sell * cut - (Vendor(id) or 0) * DEPOSIT[other]
      local profit = net - h.p
      if profit >= MIN_PROFIT and net >= h.p * 1.2 then
        out[#out + 1] = { id = id, n = NameOf(id, h), buy = h.p, sell = sell, profit = profit, qty = h.q, other = other }
      end
    end
  end
  table.sort(out, function(a, b) return a.profit > b.profit end)
  return out
end

-------------------------------------------------------------------------------
-- What the window shows. D.Build() returns:
--   meta    = { ah = "...", status = "..." }  (fixed header)
--   entries = list of
--     { kind = "head", key, text, color = {r,g,b}, cols = {4 labels}, count }
--     { kind = "deal", sec, id, n, c1, c2, c3, c4, detail, tip = {{label, value}, ...} }
--     { kind = "note", text, id, n }
-------------------------------------------------------------------------------
local function Ago(t) return ns.Data.Ago(t) end

-- Compact coin text with the game's gold/silver/copper icons.
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local function Coins(c)
  c = math.floor((c or 0) + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  -- %.0f, not %d: the game's %d stops at ~214,748g (troll listings go higher)
  if g >= 100 then return ("%.0f%s"):format(g, GOLD) end
  if g > 0 then return s > 0 and ("%d%s %d%s"):format(g, GOLD, s, SILVER) or ("%d%s"):format(g, GOLD) end
  if s > 0 then return cp > 0 and ("%d%s %d%s"):format(s, SILVER, cp, COPPER) or ("%d%s"):format(s, SILVER) end
  return ("%d%s"):format(cp, COPPER)
end
D.Coins = Coins

local SECTIONS = {
  vendor = { text = "Sure profit: buy and sell to a vendor", color = { 0.25, 1, 0.25 }, cols = { "Qty", "Buy", "Vendor", "Profit" } },
  snipe  = { text = "Cheap vs the usual price: buy and relist", color = { 0.2, 0.8, 1 }, cols = { "Qty", "Buy", "Relist", "Profit" } },
  gap    = { text = "Price gaps: cheapest far under the rest", color = { 1, 0.82, 0 }, cols = { "Qty", "Buy", "Relist", "Profit" } },
  craft  = { text = "Crafting profit (your recipes, mats bought here)", color = { 0.75, 0.55, 1 }, cols = { "Makes", "Mats", "Sells", "Profit" } },
  cross  = { text = "Cheaper here than at the other AH", color = { 0.3, 1, 0.8 }, cols = { "Listed", "Here", "There", "Each" } },
  crazy  = { text = "Crazy prices right now (sell yours)", color = { 1, 0.5, 0.25 }, cols = { "Have", "Cheapest", "Usual", "Over" } },
}

function D.Build()
  local entries, meta = {}, {}
  local pending, current -- section heading, added once its first deal shows up
  local dealCount, hidden = 0, 0
  local hiddenWhy = {}
  local function skip(why) why = why or "unknown"; hidden = hidden + 1; hiddenWhy[why] = (hiddenWhy[why] or 0) + 1 end

  local function note(text, id, n) entries[#entries + 1] = { kind = "note", text = text, id = id, n = n } end
  local function section(key, text)
    local s = SECTIONS[key]
    pending = { kind = "head", key = key, text = text or s.text, color = s.color, cols = s.cols, count = 0 }
  end
  local function deal(e)
    if e.live then
      local tag = GREEN .. "Checked live " .. Ago(e.live) .. "|r"
      e.detail = (e.detail and e.detail ~= "") and (tag .. "\n" .. e.detail) or tag
    end
    if pending then entries[#entries + 1] = pending; current = pending; pending = nil end
    e.head = current
    e.kind = "deal"
    e.head.count = e.head.count + 1
    entries[#entries + 1] = e
    dealCount = dealCount + 1
  end
  local function join(...)
    local t = {}
    for i = 1, select("#", ...) do local v = select(i, ...); if v and v ~= "" then t[#t + 1] = v end end
    return table.concat(t, "\n")
  end

  local neutral = ns.Data.IsNeutralOpen()
  local which = neutral and "neutral" or "faction"
  local key = ns.Data.CurrentKey()
  local d = DB()[key]
  local cutTxt = neutral and "15%" or "5%"

  meta.ah = (neutral and "Neutral" or "Faction") .. " auction house"
  meta.status = D.StatusText(d, cutTxt)

  if not d then
    note(GREY .. "No full scan of this auction house yet. AskAH scans by itself when you open it (once every 15 min), or click Scan.|r")
  else
    local age = time() - (d.t or 0)
    if age > 3 * 3600 then
      note(ORANGE .. ("This scan is %s old, so many of these deals are probably gone. Click Scan for fresh ones. Clicking a deal checks it live.|r"):format(
        age > 172800 and (math.floor(age / 86400) .. " days") or (math.floor(age / 3600) .. " h")))
    end
    if (d.trusted or 0) < 20 then
      note(ORANGE .. "Still learning usual prices: the \"cheap vs usual\" and \"crazy price\" checks need 3+ scans of an item.|r")
    end

    if #d.vendor > 0 then
      section("vendor")
      for i = 1, math.min(#d.vendor, MAX_ROWS) do
        local r = d.vendor[i]
        deal({ id = r.id, n = r.n, live = r.live, c1 = r.qty, c2 = Coins(r.buy), c3 = Coins(r.sell), c4 = GREEN .. "+" .. Coins(r.profit) .. "|r",
          detail = r.upto > r.buy and ("Buy every listing up to " .. Coins(r.upto) .. " each, then sell them to any vendor.") or "Buy, then sell to any vendor.",
          tip = { { "Cheapest", Money(r.buy) }, { "Up to", Money(r.upto) }, { "Vendor pays", Money(r.sell) }, { "Profit", Money(r.profit) } } })
      end
    end

    if d.v ~= DEALS_V then
      note(GREY .. "Deals from before AskAH checked whether relists sell are left out. New ones come with the next scan (or /reload for the Blizzard feed).|r")
    end
    -- Only deals whose relist really sells (Sellable above), best expected profit first
    local function relistDeals(list, key, color, sellLabel)
      local ok = {}
      for _, r in ipairs(d.v == DEALS_V and list or {}) do
        local good, info = Sellable(r.id, which, r.sell, r.qty, r.cost or r.buy * r.qty)
        if good then ok[#ok + 1] = { r = r, i = info } else skip(info.why) end
      end
      table.sort(ok, function(x, y) return x.i.profit > y.i.profit end)
      if #ok > 0 then section(key) end
      for k = 1, math.min(#ok, MAX_ROWS) do
        local r, i = ok[k].r, ok[k].i
        local lines = {}
        if key == "snipe" then
          lines[#lines + 1] = ("%d%% of the usual price (%s)"):format(r.pct, Coins(r.usual or r.sell)) .. (r.thin and (ORANGE .. " - few listed|r") or "")
        elseif not r.known then
          lines[#lines + 1] = ORANGE .. "No price history yet, check it first.|r"
        end
        local buyTxt = i.qty < r.qty and ("Buy the cheapest %d of %d (about a day of sales here)"):format(i.qty, r.qty)
          or ("Buy %d"):format(r.qty)
        if r.upto and r.upto > r.buy and i.qty >= r.qty then buyTxt = buyTxt .. ", up to " .. Coins(r.upto) .. " each" end
        lines[#lines + 1] = buyTxt .. ", relist at " .. Coins(r.sell) .. " each (just under the next listing)."
        lines[#lines + 1] = GREEN .. ("%s chance each listing sells, sells ~%s/day here|r"):format(Pct(i.chance), i.spd >= 10 and ("%d"):format(i.spd) or ("%.1f"):format(i.spd))
        local own = OwnText(r.id)
        if own then lines[#lines + 1] = GREY .. own .. "|r" end
        deal({ id = r.id, n = r.n, live = r.live, c1 = i.qty, c2 = Coins(r.buy), c3 = Coins(r.sell), c4 = color .. "~+" .. Coins(i.profit) .. "|r",
          detail = join(unpack(lines)),
          tip = { { "Buy from", Money(r.buy) }, { "Relist at", Money(r.sell) }, { sellLabel, Money(r.usual or r.nextP or r.sell) },
            { "Chance to sell", Pct(i.chance) }, { "Sells per day", ("%.1f"):format(i.spd) },
            { "Buy", i.qty .. (i.qty < r.qty and (" of " .. r.qty) or "") }, { "Profit (expected)", Money(i.profit) } } })
      end
    end
    relistDeals(d.snipe, "snipe", GREEN, "Usual price")
    relistDeals(d.gap, "gap", YELLOW, "Next listing")
  end

  local crafts = CraftDeals(which)
  if #crafts > 0 then
    local ok = {}
    for _, r in ipairs(crafts) do
      local good, info = Sellable(r.id, which, r.sell / r.made, r.made, r.cost)
      if good then ok[#ok + 1] = { r = r, i = info } else skip(info.why) end
    end
    table.sort(ok, function(x, y) return x.i.profit > y.i.profit end)
    if #ok > 0 then section("craft") end
    for k = 1, math.min(#ok, MAX_ROWS) do
      local r, i = ok[k].r, ok[k].i
      deal({ id = r.id, n = r.n, live = r.live, c1 = r.made, c2 = Coins(r.cost), c3 = Coins(r.sell), c4 = GREEN .. "~+" .. Coins(i.profit) .. "|r",
        detail = join(r.prof .. (r.missing and (" - plus " .. r.missing .. " (vendor/no price)") or ""),
          GREEN .. ("%s chance each listing sells, sells ~%.1f/day here|r"):format(Pct(i.chance), i.spd), OwnText(r.id) and (GREY .. OwnText(r.id) .. "|r")),
        tip = { { "Profession", r.prof }, { "Mats cost", Money(r.cost) }, { "Sells for", Money(r.sell) }, { "Chance to sell", Pct(i.chance) },
          { "Profit (expected)", Money(i.profit) } } })
    end
  elseif not next(ns.Data.Char().recipes or {}) then
    note(GREY .. "Open your profession windows once so AskAH can check crafting profit too.|r")
  end

  local cross = CrossDeals(which)
  if #cross > 0 then
    local otherName = neutral and "faction" or "neutral"
    local ok = {}
    for _, r in ipairs(cross) do
      -- per item: buy one here, sell it there
      local good, info = Sellable(r.id, r.other, r.sell, 1, r.buy)
      if good then ok[#ok + 1] = { r = r, i = info } else skip(info.why) end
    end
    table.sort(ok, function(x, y) return x.i.profit > y.i.profit end)
    if #ok > 0 then section("cross", ("Cheaper here than at the %s AH"):format(otherName)) end
    for k = 1, math.min(#ok, MAX_ROWS) do
      local r, i = ok[k].r, ok[k].i
      local most = math.max(1, math.floor(i.spd * SELL_DAYS))
      deal({ id = r.id, n = r.n, live = r.live, c1 = r.qty or "", c2 = Coins(r.buy), c3 = Coins(r.sell), c4 = GREEN .. "~+" .. Coins(i.profit) .. "|r",
        detail = ("Profit is per item (expected). %s chance each sells at the %s AH, ~%.1f sell a day there: buy %d at most."):format(Pct(i.chance), otherName, i.spd, most),
        tip = { { "Price here", Money(r.buy) }, { "Sells there", Money(r.sell) }, { "Chance to sell", Pct(i.chance) }, { "Profit each (expected)", Money(i.profit) } } })
    end
  end

  if d and #d.crazy > 0 then
    local own = Owned()
    section("crazy")
    for i = 1, math.min(#d.crazy, MAX_ROWS) do
      local r = d.crazy[i]
      local have = own[r.id]
      local detail
      if have and have > 0 then
        local spd, n = Rate(r.id, which)
        detail = GREEN .. ("You have %d: sell now.|r "):format(have) ..
          RateText(spd, n):gsub("^%l", string.upper) .. " here; at that price it may not sell, so list a bit under the cheapest."
      end
      deal({ id = r.id, n = r.n, live = r.live, c1 = (have and have > 0) and (GREEN .. have .. "|r") or (GREY .. "0|r"),
        c2 = Coins(r.buy), c3 = Coins(r.sell), c4 = ORANGE .. ("%.1fx"):format(r.x) .. "|r", detail = detail,
        tip = { { "Cheapest now", Money(r.buy) }, { "Usually", Money(r.sell) }, { "Over usual", ("%.1fx"):format(r.x) } } })
    end
  end

  -- Forever Black Market ceiling
  local prices = ns.Data.Prices(which)
  for id, cap in pairs(BLACK_MARKET) do
    local e = prices[id]
    if e and Fresh(e, 48) and e.p > cap then
      note(ORANGE .. ("%s is %s here: Mister Graphed (Black Market) sells it for %s.|r"):format(NameOf(id, e), Coins(e.p), Coins(cap)), id, NameOf(id, e))
    end
  end

  if hidden > 0 then
    local parts = {}
    for _, k in ipairs({ "unknown", "slow", "chance", "yours", "thin" }) do
      if hiddenWhy[k] then parts[#parts + 1] = ("%d %s"):format(hiddenWhy[k], WHY[k]) end
    end
    note(GREY .. ("%d deal(s) left out because the relist probably wouldn't sell: %s.|r"):format(hidden, table.concat(parts, ", ")))
  end
  if dealCount == 0 then
    note(GREY .. "No deals found that clear 20s expected profit and sell at the relist price. Check again after the next scan.|r")
  end
  if d then
    local measured, total = 0, 0
    for _, e in pairs(ns.Data.Prices(which)) do
      total = total + 1
      if e.spd and (e.spdN or 0) >= 1 then measured = measured + 1 end
    end
    note(GREY .. ("Will it sell: measured for %d of %d items at this AH so far. A sell rate needs two looks at the same AH 5 min to 6 h apart: listings gone the second time count as sold. AskAH rescans every 15 min while you stay at the AH, and your own searches count too. Scans more than 6 h apart can't be compared. Your own sales history is shown where it exists.|r"):format(measured, total))
  end
  return entries, meta
end

-- Header line: scan age, and when the next scan comes.
function D.StatusText(d, cutTxt)
  local parts = { ("Profit after the %s AH cut"):format(cutTxt or "5%") }
  if ns.Data.IsScanning and ns.Data.IsScanning() then
    parts[#parts + 1] = YELLOW .. "scanning now...|r"
  else
    parts[#parts + 1] = d and ((d.src == "feed" and "Blizzard data from " or "scanned ") .. Ago(d.t)) or "not scanned yet"
    if ns.Data.NextScanIn and ns.Data.IsAHOpen and ns.Data.IsAHOpen() then
      local wait = ns.Data.NextScanIn()
      if wait > 0 then parts[#parts + 1] = ("next scan in %d min"):format(math.ceil(wait / 60))
      elseif AskAHDB.autoScan == false then parts[#parts + 1] = GREEN .. "scan ready|r"
      else parts[#parts + 1] = GREEN .. "rescanning soon|r" end
    end
  end
  return table.concat(parts, " - ")
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local win, scroll, child
local pools = { head = {}, deal = {}, note = {} }
local used = {}
local sticky, stickyClip -- section heading pinned to the top while scrolling
local headsY = {}        -- { {y = top of heading in the list, e = entry}, ... }
local COLW = { 46, 88, 88, 92 } -- Qty, Buy, Sell, Profit (right-aligned)
local ICON = 18
local DEF_W, DEF_H = 620, 470

-- Take the auction house to an item: switch to the Browse/Buy tab, search for
-- the name, and (new-style AH) open the item's own listings when the results
-- come in. Each step is tried on its own so one missing UI piece doesn't stop
-- the rest; if nothing worked, say so in chat instead of failing silently.
local jumpTo -- { id =, name =, t =, got = } waiting for browse results to open the item
local jumpFrame = CreateFrame("Frame")
local Now = GetTime or time

-- Open the browse result for this item, if the results list has it. The
-- result carries the AH's own item key (with the right item level for gear),
-- so the item's listings open just as if you had clicked it.
local function OpenResult(id)
  if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults and AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult) then return false end
  local results = try(C_AuctionHouse.GetBrowseResults) or {}
  for _, r in ipairs(results) do
    if r.itemKey and r.itemKey.itemID == id then
      return (pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, r)), #results
    end
  end
  return false, #results
end

-- Last resort: open the item by a key built from its id. Only right for
-- stackable goods (commodities); gear needs the item level the AH gives it.
local function OpenDirect(id)
  local f = AuctionHouseFrame
  if not (id and f and f:IsShown() and f.SelectBrowseResult and C_AuctionHouse and C_AuctionHouse.MakeItemKey) then return false end
  local ok, key = pcall(C_AuctionHouse.MakeItemKey, id)
  if not ok or not key then return false end
  return (pcall(f.SelectBrowseResult, f, { itemKey = key, minPrice = 0, totalQuantity = 0, containsOwnerItem = false }))
end

local function StopJump() jumpFrame:UnregisterAllEvents(); jumpTo = nil end

jumpFrame:SetScript("OnEvent", function(self, event)
  if not jumpTo or Now() - jumpTo.t > 15 then StopJump() return end
  if event == "AUCTION_HOUSE_CLOSED" then StopJump() return end
  local opened, n = OpenResult(jumpTo.id)
  if (n or 0) > 0 then jumpTo.got = true end
  if opened then StopJump() end
end)

local function WatchResults(id, name)
  jumpTo = { id = id, name = name, t = Now() }
  local me = jumpTo
  for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_CLOSED" }) do
    pcall(jumpFrame.RegisterEvent, jumpFrame, e)
  end
  if not (C_Timer and C_Timer.After) then return end
  -- the results may already be there (same search as last time)
  C_Timer.After(0.3, function() if jumpTo == me and OpenResult(id) then StopJump() end end)
  -- if the item never shows up in the results, say why instead of doing nothing
  C_Timer.After(5, function()
    if jumpTo ~= me then return end
    if OpenResult(id) then StopJump() return end
    StopJump()
    if me.got then
      ns.Print(("%s isn't listed at this AH right now (the search found other items, not it). It may have sold since the deal was spotted."):format(name))
    elseif OpenDirect(id) then
      -- no browse results came back (throttled or empty search); open it by id
    else
      ns.Print(("the AH didn't answer the search for %s. Click it again in a moment."):format(name))
    end
  end)
end

local function SearchAH(name, id, tries)
  -- use the item's real name: a deal spotted by the Blizzard feed may not have
  -- one yet ("item 12345"), and the AH can't search for that
  if id then
    local real = NameOf(id)
    if real and not real:match("^item %d+$") then name = real end
  end
  if (not name or name == "" or name:match("^item %d+$")) and id then
    tries = tries or 0
    if tries < 6 and C_Timer and C_Timer.After then
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      C_Timer.After(0.5, function() SearchAH(name, id, tries + 1) end)
    else
      ns.Print(("couldn't get the name of item %d from the game to search for it. Try again in a few seconds."):format(id))
    end
    return
  end
  if not name or name == "" then return end
  local did, errs = {}, {}
  local function step(label, f, ...)
    local ok, err = pcall(f, ...)
    if ok then did[#did + 1] = label else errs[#errs + 1] = label .. ": " .. tostring(err) end
    return ok
  end

  -- Old-style AH window (AuctionFrame with a Browse tab)
  if AuctionFrame and AuctionFrame:IsShown() and BrowseName then
    if AuctionFrameTab1 and AuctionFrame.selectedTab ~= 1 then
      step("tab", function() AuctionFrameTab1:Click() end)
    end
    step("name", function() BrowseName:SetText(name); BrowseName:ClearFocus() end)
    if AuctionFrameBrowse_Search then
      step("search", AuctionFrameBrowse_Search)
    elseif BrowseSearchButton then
      step("search", function() BrowseSearchButton:Click() end)
    end

  -- New-style AH window (AuctionHouseFrame with a search bar)
  elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    -- the AH ignores a search sent too soon after the last one; wait for it
    tries = tries or 0
    if C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
      and try(C_AuctionHouse.IsThrottledMessageSystemReady) == false and tries < 8 and C_Timer and C_Timer.After then
      C_Timer.After(0.5, function() SearchAH(name, id, tries + 1) end)
      return
    end
    local f = AuctionHouseFrame
    if f.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
      step("tab", f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy)
    elseif AuctionHouseFrameBuyTab then
      step("tab", function() AuctionHouseFrameBuyTab:Click() end)
    end
    local bar = f.SearchBar
    local box = bar and bar.SearchBox
    local searched = false
    if box then step("name", function() box:SetText(name); box:ClearFocus() end) end
    if bar and bar.StartSearch then
      searched = step("search", bar.StartSearch, bar)
    elseif bar and bar.SearchButton then
      searched = step("search", function() bar.SearchButton:Click() end)
    end
    if not searched and C_AuctionHouse and C_AuctionHouse.SendBrowseQuery then
      searched = step("query", C_AuctionHouse.SendBrowseQuery, { searchString = name, sorts = {}, filters = {} })
    end
    -- open the item's listings when its result comes in
    if id then WatchResults(id, name) end
  else
    ns.Print("open the auction house first, then click a deal to find it there.")
    return
  end

  local found = false
  for _, d in ipairs(did) do if d == "search" or d == "query" then found = true end end
  if not found then
    ns.Print(("couldn't search the AH for %s. Worked: %s. Failed: %s"):format(name,
      #did > 0 and table.concat(did, ", ") or "nothing", #errs > 0 and table.concat(errs, "; ") or "no search box found"))
  elseif #errs > 0 then
    ns.Print(("looking up %s at the AH - didn't work: %s"):format(name, table.concat(errs, "; ")))
  end
end

local function Collapsed()
  AskAHDB.dealsCollapsed = AskAHDB.dealsCollapsed or {}
  return AskAHDB.dealsCollapsed
end

local function Tex(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
  return t
end

local function Font(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- Right-aligned column cells; returns the total width they take.
local function MakeCols(f, template, point, y)
  f.cols = {}
  local right = -6
  for i = #COLW, 1, -1 do
    local fs = Font(f, template, "RIGHT")
    fs:SetWidth(COLW[i] - 6)
    fs:SetPoint(point, f, point, right, y)
    fs:SetWordWrap(false)
    f.cols[i] = fs
    right = right - COLW[i]
  end
  return -right
end

local function ItemLook(id)
  local _, _, quality, _, _, _, _, _, _, icon = try(GII, id)
  if not icon then
    icon = try(C_Item and C_Item.GetItemIconByID, id) or try(GetItemIcon, id)
  end
  local col = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  return icon, col, quality ~= nil
end

local waiting = {} -- itemIDs shown without their name/icon loaded yet

local function RowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.id then
    pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
    if self.tip then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("AskAH", 0.2, 0.8, 1)
      for _, p in ipairs(self.tip) do GameTooltip:AddDoubleLine(p[1], p[2], 0.7, 0.7, 0.7, 1, 1, 1) end
    end
    if self.detailText and self.detailText ~= "" then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(self.detailText, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: search the AH for it", 0.5, 0.5, 0.5)
  elseif self.text then
    GameTooltip:AddLine(self.text:GetText() or "", 1, 1, 1, true)
  end
  GameTooltip:Show()
end

local function NewHead(parent)
  local b = CreateFrame("Button", nil, parent or child)
  b.bg = Tex(b, "BACKGROUND", 1, 1, 1, 1)
  b.bg:SetAllPoints()
  b.bar = Tex(b, "ARTWORK", 1, 1, 1, 1)
  b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
  b.line = Tex(b, "ARTWORK", 1, 1, 1, 1)
  b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(1)
  b.toggle = Font(b, "GameFontNormalSmall")
  b.toggle:SetPoint("LEFT", 8, 0)
  b.toggle:SetWidth(12)
  b.label = Font(b, "GameFontNormal")
  b.label:SetPoint("LEFT", 22, 0)
  b.label:SetWordWrap(false)
  local colsW = MakeCols(b, "GameFontDisableSmall", "RIGHT", 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -colsW - 4, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    local c = Collapsed()
    c[self.key] = not c[self.key] or nil
    D.Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.label:GetText() or "", 1, 1, 1)
    GameTooltip:AddLine("Click to " .. (Collapsed()[self.key] and "show" or "hide") .. " this section", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function NewDeal()
  local b = CreateFrame("Button", nil, child)
  b.bg = Tex(b, "BACKGROUND", 1, 1, 1, 0.035)
  b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("TOPLEFT", 8, -2)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local colsW = MakeCols(b, "GameFontHighlightSmall", "TOPRIGHT", -6)
  b.name = Font(b, "GameFontHighlight")
  b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -2)
  b.name:SetPoint("RIGHT", b, "RIGHT", -colsW - 6, 0)
  b.name:SetWordWrap(false)
  b.detail = Font(b, "GameFontDisableSmall")
  b.detail:SetPoint("TOPLEFT", b.icon, "BOTTOMRIGHT", 6, -2)
  b.detail:SetWordWrap(true)
  b.colsW = colsW
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    if self.id then lastClicked = { id = self.id, t = time() } end
    SearchAH(self.n, self.id)
  end)
  b:SetScript("OnEnter", RowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function NewNote()
  local b = CreateFrame("Button", nil, child)
  b.text = Font(b, "GameFontHighlightSmall")
  b.text:SetPoint("TOPLEFT", 8, -3)
  b.text:SetWordWrap(true)
  b:SetScript("OnClick", function(self)
    if self.id then lastClicked = { id = self.id, t = time() } end
    SearchAH(self.n, self.id)
  end)
  b:SetScript("OnEnter", function(self) if self.id then RowTooltip(self) end end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local MAKERS = { head = function() return NewHead(child) end, deal = NewDeal, note = NewNote }

local function PaintHead(b, e, collapsed)
  local c = e.color
  b.key = e.key
  b.bar:SetVertexColor(c[1], c[2], c[3], 1)
  b.line:SetVertexColor(c[1], c[2], c[3], 0.35)
  b.bg:SetVertexColor(c[1], c[2], c[3], 0.10)
  b.label:SetText(e.text .. "  |cff888888(" .. e.count .. ")|r")
  b.label:SetTextColor(c[1], c[2], c[3])
  b.toggle:SetText(collapsed[e.key] and "+" or "-")
  for i = 1, 4 do b.cols[i]:SetText(collapsed[e.key] and "" or e.cols[i]) end
end

-- Pin the heading of the section at the top of the view. When the next
-- heading scrolls up to it, the pinned one is pushed up and out of the way.
local function UpdateSticky()
  if not sticky then return end
  local off = scroll:GetVerticalScroll() or 0
  local cur, nxt
  for i, h in ipairs(headsY) do
    if h.y <= off then cur, nxt = h, headsY[i + 1] else break end
  end
  if not cur or off <= 0 then stickyClip:Hide() return end
  PaintHead(sticky, cur.e, Collapsed())
  local push = 0
  if nxt and stickyClip.clips then push = math.max(0, 24 - (nxt.y - off)) end
  if nxt and not stickyClip.clips and nxt.y - off < 24 then PaintHead(sticky, nxt.e, Collapsed()) end
  sticky:ClearAllPoints()
  sticky:SetPoint("TOPLEFT", stickyClip, "TOPLEFT", 0, push)
  sticky:SetPoint("TOPRIGHT", stickyClip, "TOPRIGHT", 0, push)
  sticky:SetHeight(22)
  stickyClip:Show()
end
local function Take(kind)
  used[kind] = (used[kind] or 0) + 1
  local p = pools[kind]
  local f = p[used[kind]]
  if not f then f = MAKERS[kind](); p[used[kind]] = f end
  f:Show()
  return f
end

local function ContentWidth()
  local w = scroll and scroll:GetWidth() or 0
  if not w or w < 100 then w = (win:GetWidth() or DEF_W) - 40 end
  return w
end

local function Place(f, y, h, w)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
  f:SetSize(w, h)
end

function D.Refresh()
  if not win or not win:IsShown() then return end
  local ok, entries, meta = pcall(D.Build)
  if not ok then
    entries, meta = { { kind = "note", text = RED .. "AskAH deals error: " .. tostring(entries) .. "|r" } }, {}
  end
  win.ahText:SetText(meta.ah or "")
  win.status:SetText(meta.status or "")

  for kind, p in pairs(pools) do for _, f in ipairs(p) do f:Hide() end; used[kind] = 0 end
  local w = ContentWidth()
  child:SetWidth(w)
  local collapsed = Collapsed()
  local y, stripe = 2, false
  wipe(waiting)
  wipe(headsY)

  for _, e in ipairs(entries) do
    if e.kind == "head" then
      y = y + 8
      local b = Take("head")
      PaintHead(b, e, collapsed)
      headsY[#headsY + 1] = { y = y, e = e }
      Place(b, y, 22, w)
      y = y + 22 + 2
      stripe = false
    elseif e.kind == "deal" then
      if not (e.head and collapsed[e.head.key]) then
        local b = Take("deal")
        b.id, b.n, b.tip, b.detailText = e.id, e.n, e.tip, e.detail
        local icon, qc, known = ItemLook(e.id)
        if not known then waiting[e.id] = true end
        b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.name:SetText(e.n or "")
        if qc then b.name:SetTextColor(qc.r, qc.g, qc.b) else b.name:SetTextColor(1, 1, 1) end
        b.cols[1]:SetText(e.c1 ~= nil and tostring(e.c1) or "")
        b.cols[2]:SetText(e.c2 or ""); b.cols[3]:SetText(e.c3 or ""); b.cols[4]:SetText(e.c4 or "")
        local h = ICON + 4
        if e.detail and e.detail ~= "" then
          b.detail:SetWidth(w - ICON - 22)
          b.detail:SetText(e.detail)
          b.detail:Show()
          h = h + math.ceil(b.detail:GetStringHeight()) + 4
        else
          b.detail:SetText("")
          b.detail:Hide()
        end
        b.bg:SetAlpha(stripe and 1 or 0)
        stripe = not stripe
        Place(b, y, h, w)
        y = y + h
      end
    else
      local b = Take("note")
      b.id, b.n, b.tip, b.detailText = e.id, e.n, nil, nil
      b.text:SetWidth(w - 16)
      b.text:SetText(e.text)
      b:EnableMouse(e.id ~= nil)
      local h = math.ceil(b.text:GetStringHeight()) + 6
      y = y + 4
      Place(b, y, h, w)
      y = y + h
    end
  end
  child:SetHeight(y + 8)
  UpdateSticky()
end

-- Redraw soon, at most twice a second (live price changes, bag changes).
local refreshQueued = false
function D.QueueRefresh()
  if refreshQueued or not win or not win:IsShown() then return end
  refreshQueued = true
  local function go() refreshQueued = false; D.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, go) else go() end
end

-- While the window is open: keep the scan age/countdown current, and rescan
-- when the server allows it again and you haven't searched in the last 2 min
-- (a full scan replaces what the Browse tab shows).
local TICK, ticks = 15, 0
local function Tick()
  local d = DB()[ns.Data.CurrentKey()]
  win.status:SetText(D.StatusText(d, ns.Data.IsNeutralOpen() and "15%" or "5%"))
  local D_ = ns.Data
  if D_.IsAHOpen and D_.IsAHOpen() and AskAHDB.autoScan ~= false and D_.NextScanIn and D_.NextScanIn() == 0
      and not D_.IsScanning() and time() - (D_.LastSearch() or 0) > 120 then
    D_.Scan(true)
  end
  ticks = ticks + 1
  if ticks % 4 == 0 then D.QueueRefresh() end -- "checked 3 min ago" etc. once a minute
end

-- Item names/icons arrive from the server a moment later: redraw once then.
local redrawQueued = false
local function QueueRedraw(_, _, itemID)
  if redrawQueued or not itemID or not waiting[itemID] or not win or not win:IsShown() then return end
  redrawQueued = true
  local function go() redrawQueued = false; D.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, go) else go() end
end

local function Create()
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  win = CreateFrame("Frame", "AskAHDealsWindow", UIParent, tmpl)
  local size = AskAHDB and AskAHDB.dealsSize
  win:SetSize(size and size[1] or DEF_W, size and size[2] or DEF_H)
  win:SetMovable(true)
  win:SetResizable(true)
  if win.SetResizeBounds then win:SetResizeBounds(500, 280, 1000, 1000)
  elseif win.SetMinResize then win:SetMinResize(500, 280); if win.SetMaxResize then win:SetMaxResize(1000, 1000) end end
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
  win:SetClampedToScreen(true)
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)

  if win.SetBackdrop then
    win:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    win:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    win:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  else
    local bg = Tex(win, "BACKGROUND", 0.05, 0.05, 0.07, 0.95)
    bg:SetAllPoints()
  end

  -- Title bar
  local bar = Tex(win, "BORDER", 1, 1, 1, 0.06)
  bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("TOPRIGHT", -4, -4); bar:SetHeight(48)
  local title = Font(win, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("AskAH |cffffffffDeals|r")
  win.ahText = Font(win, "GameFontHighlight")
  win.ahText:SetPoint("LEFT", title, "RIGHT", 10, -1)
  win.ahText:SetTextColor(0.2, 0.8, 1)
  win.status = Font(win, "GameFontDisableSmall")
  win.status:SetPoint("TOPLEFT", 14, -32)

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  local scan = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  scan:SetSize(80, 22)
  scan:SetPoint("TOPRIGHT", -34, -14)
  scan:SetText("Scan")
  scan:SetScript("OnClick", function() ns.Data.Scan() end)

  local div = Tex(win, "BORDER", 1, 1, 1, 0.15)
  div:SetPoint("TOPLEFT", 4, -52); div:SetPoint("TOPRIGHT", -4, -52); div:SetHeight(1)

  -- Footer
  local foot = Font(win, "GameFontDisableSmall")
  foot:SetPoint("BOTTOMLEFT", 14, 9)
  foot:SetPoint("RIGHT", win, "RIGHT", -30, 0)
  foot:SetWordWrap(false)
  foot:SetText("Hover a line for details, click it to search the AH. Click a heading to fold it. /askah deals off stops the pop-up.")
  local fdiv = Tex(win, "BORDER", 1, 1, 1, 0.15)
  fdiv:SetPoint("BOTTOMLEFT", 4, 26); fdiv:SetPoint("BOTTOMRIGHT", -4, 26); fdiv:SetHeight(1)

  scroll = CreateFrame("ScrollFrame", "AskAHDealsScroll", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -56)
  scroll:SetPoint("BOTTOMRIGHT", -28, 30)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(DEF_W - 40, 1)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then child:SetWidth(w) end end)
  scroll:HookScript("OnVerticalScroll", UpdateSticky)
  scroll:HookScript("OnScrollRangeChanged", UpdateSticky)

  -- Sticky heading: sits over the top of the list, above the rows.
  stickyClip = CreateFrame("Frame", nil, win)
  stickyClip:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  stickyClip:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
  stickyClip:SetHeight(24)
  stickyClip:SetFrameLevel(scroll:GetFrameLevel() + 10)
  if stickyClip.SetClipsChildren then stickyClip:SetClipsChildren(true); stickyClip.clips = true end
  sticky = NewHead(stickyClip)
  local solid = sticky:CreateTexture(nil, "BACKGROUND", nil, -8) -- hides rows passing underneath
  if solid.SetColorTexture then solid:SetColorTexture(0.05, 0.05, 0.07, 1) else solid:SetTexture(0.05, 0.05, 0.07, 1) end
  solid:SetAllPoints()
  sticky:SetFrameLevel(stickyClip:GetFrameLevel() + 1)
  stickyClip:Hide()

  -- Resize grip
  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    win:StopMovingOrSizing()
    if AskAHDB then AskAHDB.dealsSize = { math.floor(win:GetWidth()), math.floor(win:GetHeight()) } end
    D.Refresh()
  end)

  local acc = 0
  win:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc >= TICK then acc = 0; pcall(Tick) end
  end)
  win:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  win:SetScript("OnEvent", QueueRedraw)
  tinsert(UISpecialFrames, "AskAHDealsWindow")
end

function D.Show()
  if not win then Create() end
  local ah = (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame)
          or (AuctionFrame and AuctionFrame:IsShown() and AuctionFrame)
  if ah and not win.moved then
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, -10)
  elseif not ah and not win.moved then
    win:ClearAllPoints()
    win:SetPoint("CENTER")
  end
  win:Show()
  D.Refresh()
end

function D.Hide() if win then win:Hide() end end
function D.Toggle() if win and win:IsShown() then D.Hide() else D.Show() end end

local ev = CreateFrame("Frame")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    if AskAHDB and AskAHDB.dealsPopup ~= false then
      -- after Data has worked out which AH this is
      if C_Timer and C_Timer.After then C_Timer.After(0.3, D.Show) else D.Show() end
    end
  else
    D.Hide()
  end
end)
