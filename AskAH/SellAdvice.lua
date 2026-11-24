-- SellAdvice.lua
-- Auction house or vendor? Works out what one listing of an item is really
-- worth at each auction house, counting:
--   * the AH cut (faction 5%, neutral 15%)
--   * the deposit, lost every time a listing expires
--   * the chance it sells. Three sources, blended by how much each one knows:
--     1. sell-through: the hourly Blizzard feed follows every auction by ID;
--        one that vanishes before its time is up sold, one that vanishes
--        right when it ran out expired. That gives "x% of listings sell",
--        per item, by place in the queue and by price against usual, with
--        items like it (kind, quality, demand) filling in where it's thin.
--     2. demand vs competition: units sold per day against units listed.
--     3. your own record for the item: sold vs came back by mail.
--   * relisting up to 3 times, then vendoring what's left
-- and compares that with the vendor price (Blizzard API data first).
-- ns.Sell.Advise(itemID, count) returns a table; Tooltip.lua shows it.
local _, ns = ...
local S = {}
ns.Sell = S
-- for other addons (AskQuest values quest rewards with it)
AskAHSell = { Advise = function(...) return S.Advise(...) end }

local CUT = { faction = 0.05, neutral = 0.15 }
-- Deposit as a share of the vendor price for one 12h listing. Default
-- estimate; replaced by what your own AH mail shows once there are a few sales.
local DEPOSIT_DEFAULT = { faction = 0.05, neutral = 0.15 }
local LISTING_DAYS = 1     -- a typical listing (12-48h)
local TRIES = 3            -- relist up to 3 times, then vendor it

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
end

-- Vendor price: Blizzard API data first, then the game.
function S.Vendor(itemID)
  local b = AskAHBlizzAPI and AskAHBlizzAPI.Item(itemID)
  if b then return b.sell or 0 end
  local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  return select(11, try(GII, itemID)) or 0
end

-- Your AH history across all characters: sold / didn't sell, per AH, for this
-- item; and the deposit rate your mail has shown (deposit / vendor value).
local function History(itemID)
  local h = { faction = { sold = 0, unsold = 0, lost = 0, cut = 0, got = 0 },
              neutral = { sold = 0, unsold = 0, lost = 0, cut = 0, got = 0 } }
  for _, c in pairs(AskAHDB and AskAHDB.chars or {}) do
    for _, e in ipairs(c.sales or {}) do
      local w = (e.ah == "neutral") and "neutral" or "faction"
      if e.id == itemID then
        local x = h[w]
        if e.kind == "expired" then x.unsold = x.unsold + 1; x.lostN = (x.lostN or 0) + (e.q or 1)
        elseif not e.kind then
          x.sold = x.sold + 1; x.cut = x.cut + (e.cut or 0); x.got = x.got + (e.got or 0)
          if e.dep then x.depPaid = (x.depPaid or 0) + e.dep end
        end
      end
    end
  end
  -- what your posts that expired were listed at (from saved predictions)
  for _, pr in ipairs(AskAHDB and AskAHDB.preds or {}) do
    if pr.id == itemID and pr.y == 0 and pr.unit then
      local x = h[pr.ah == "neutral" and "neutral" or "faction"]
      x.failUnit = math.min(x.failUnit or math.huge, pr.unit)
      -- the deposit you actually paid for it (instead of an estimate)
      if pr.dep and pr.dep > 0 then x.lost = x.lost + pr.dep; x.lostN = math.max(0, (x.lostN or 0) - (pr.q or 1)) end
    end
  end
  return h
end

---------------------------------------------------------------------------
-- Other addons' data, used when they're installed (all optional):
--  * TradeSkillMaster (supports WoW: Forever since 4.15; its free desktop app
--    downloads region-wide data): sale rate and sold per day across the
--    whole region, and market values.
--  * Auctionator: the price from its own AH scans.
---------------------------------------------------------------------------
local function TSM(src, itemID)
  if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
  local ok, v = pcall(TSM_API.GetCustomPriceValue, src, "i:" .. itemID)
  if ok and type(v) == "number" then return v end
end
function S.TSMData(itemID)
  if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
  local rate = TSM("DBRegionSaleRate", itemID)
  if rate and rate > 1 then rate = rate / 1000 end -- some versions give it per mille
  return { rate = rate, perDay = TSM("DBRegionSoldPerDay", itemID), market = TSM("DBMarket", itemID),
           region = TSM("DBRegionMarketAvg", itemID), historical = TSM("DBHistorical", itemID) }
end
function S.AuctionatorPrice(itemID)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (A and A.GetAuctionPriceByItemID) then return nil end
  local ok, v = pcall(A.GetAuctionPriceByItemID, "AskAH", itemID)
  if ok and type(v) == "number" and v > 0 then return v end
end

local depCache, depCacheT = nil, 0
local function DepositRates()
  if depCache and time() - depCacheT < 300 then return depCache end
  local sum, n = { faction = 0, neutral = 0 }, { faction = 0, neutral = 0 }
  for _, c in pairs(AskAHDB and AskAHDB.chars or {}) do
    for _, e in ipairs(c.sales or {}) do
      if not e.kind and e.dep and e.dep > 0 and e.id then
        local v = S.Vendor(e.id) * (e.q or 1)
        if v > 0 then
          local w = (e.ah == "neutral") and "neutral" or "faction"
          local r = e.dep / v
          if r > 0.005 and r < 2 then sum[w], n[w] = sum[w] + r, n[w] + 1 end
        end
      end
    end
  end
  depCache = {}
  for w, d in pairs(DEPOSIT_DEFAULT) do depCache[w] = n[w] >= 3 and (sum[w] / n[w]) or d end
  depCacheT = time()
  return depCache
end

-- Chance one listing (at the lowest price) sells before it expires, from demand.
-- spd = units sold per day; listed = units up now; count = your stack.
local function MarketChance(spd, listed, count, hoursSeen)
  if not spd then return nil end
  -- "none sold" in a day of watching isn't "never sells": add half a sale
  -- over the time watched (fades out as the item's history grows)
  local days = math.max(0.5, (hoursSeen or 24) / 24)
  spd = spd + 0.5 / days
  -- buyers take the cheapest first; you undercut, so you're first in line,
  -- but a crowded market gets undercut again before your 12h are up.
  local p = 1 - math.exp(-spd * LISTING_DAYS / math.max(count, 1))
  local supplyDays = (listed or 0) / spd
  if supplyDays > 7 then p = p * 0.6 elseif supplyDays > 2 then p = p * 0.8 end
  return math.max(0.02, math.min(0.97, p))
end

-- Lowest price at every auction house in the Blizzard feed (both factions'
-- and neutral), leaving out one that equals `own` (this AH's own price).
local function OtherHouseMin(itemID, own)
  local H = type(AskAHFeed) == "table" and AskAHFeed.houses
  if not H then return nil end
  local best, skipped = nil, false
  for _, h in pairs(H) do
    local str = h.items and h.items[itemID]
    local v = str and tonumber(str:match("^(%d+)"))
    if v and v > 0 then
      if not skipped and own and v == own then skipped = true
      elseif not best or v < best then best = v end
    end
  end
  return best
end
S.OtherHouseMin = OtherHouseMin

---------------------------------------------------------------------------
-- Sell-through from the Blizzard feed, by place in the queue and by price.
-- The fetcher follows every listing at your auction houses and counts, per
-- item, how many sold and how many expired, grouped by
--   queue: how many days of sales were listed cheaper (Q_NAMES)
--   price: the listing's price against the item's usual price (P_NAMES)
-- Items with few listings borrow from items like them: same kind (cloth,
-- armor, potions...), same quality, similar demand; then all items at that
-- AH. That is what gold-making guides say from experience (trade goods and
-- consumables sell, green gear is slow, overpriced listings sit), measured
-- on your own auction houses instead.
---------------------------------------------------------------------------
local Q_N, P_N = 6, 7
local Q_NAMES = { "the cheapest", "under 6h of sales cheaper", "under a day of sales cheaper",
                  "1-3 days of sales cheaper", "3-10 days of sales cheaper", "over 10 days of sales cheaper" }
local P_LIMITS = { 0.8, 0.95, 1.05, 1.2, 1.5, 2.5 }
local P_NAMES = { "under 80% of usual", "80-95% of usual", "about the usual price", "105-120% of usual",
                  "120-150% of usual", "150-250% of usual", "over 2.5x usual" }
local CLASS_NAMES = { [0] = "consumables", [1] = "bags", [2] = "weapons", [3] = "gems", [4] = "armor", [5] = "reagents",
                      [6] = "ammo", [7] = "trade goods", [9] = "recipes", [11] = "quivers", [12] = "quest items",
                      [13] = "keys", [15] = "misc items" }
local QUALITY_NAMES = { [0] = "grey", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }
S.Q_NAMES, S.P_NAMES = Q_NAMES, P_NAMES

local function Tier(spd)
  spd = spd or 0
  if spd < 0.2 then return 1 elseif spd < 1 then return 2 elseif spd < 5 then return 3 elseif spd < 25 then return 4 end
  return 5
end
local TIER_NAMES = { "barely sells", "sells under 1 a day", "sells 1-5 a day", "sells 5-25 a day", "sells 25+ a day" }

-- item kind and quality: Blizzard API data first, then the game
local kindCache = {}
local function Kind(itemID)
  local k = kindCache[itemID]
  if k ~= nil then return k or nil end
  local cls, q
  local b = AskAHBlizzAPI and AskAHBlizzAPI.Item and AskAHBlizzAPI.Item(itemID)
  if b then cls, q = b.classID, b.quality end
  if not cls then
    local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local r = { try(GII, itemID) }
    if r[1] then q, cls = r[3], r[12] end
  end
  k = cls and (cls .. ":" .. (q or 1)) or false
  kindCache[itemID] = k
  return k or nil
end
S.Kind = Kind
function S.KindName(itemID)
  local k = Kind(itemID)
  if not k then return nil end
  local c, q = k:match("^(%d+):(%d+)$")
  c, q = tonumber(c), tonumber(q)
  local cn = CLASS_NAMES[c] or "items like it"
  if c == 2 or c == 4 then return (QUALITY_NAMES[q] or "") .. " " .. cn end
  return cn
end

-- Has the feed seen this AH long enough to know expiries? Listings last up to
-- 48h, so for two days it sees sales sooner than expiries. Without time_left
-- it also has to learn the listing lengths first.
local function FeedWatched(w)
  local I = ns.Feed and ns.Feed.Info and ns.Feed.Info[w]
  if not (I and I.since and I.t) then return 0, I end
  if not I.hasTL and (I.durations or "") == "" then return 0, I end
  -- with time left in the data, sold and expired are both seen from the first
  -- hour; a few hours give enough listings. Without it, two days.
  local ramp = I.hasTL and (6 * 3600) or (50 * 3600)
  return math.max(0, math.min(1, (I.t - I.since) / ramp)), I
end
S.FeedWatched = FeedWatched

local function Add(t, key, arr, n)
  local x = t[key]
  if not x then x = {}; for i = 1, n * 2 do x[i] = 0 end; t[key] = x end
  for i = 1, n * 2 do x[i] = x[i] + (arr[i] or 0) end
end
local pools, poolsT = {}, {}
local function Pools(w)
  if pools[w] and time() - (poolsT[w] or 0) < 600 then return pools[w] end
  local P = { q = {}, p = {}, n = 0 }
  for id, e in pairs(ns.Data.Prices(w) or {}) do
    if e.stQ and e.stP then
      local tier, kind = Tier(e.spd), Kind(id) or "?"
      for _, key in ipairs({ "all", "t" .. tier, kind .. "/" .. tier }) do
        Add(P.q, key, e.stQ, Q_N); Add(P.p, key, e.stP, P_N)
      end
      for i = 1, Q_N * 2 do P.n = P.n + (e.stQ[i] or 0) end
    end
  end
  pools[w], poolsT[w] = P, time()
  return P
end
S.Pools = Pools

-- chain: all items at this AH -> same demand -> same kind and demand -> this
-- item, each level pulled toward the one before. Rates never rise further
-- back in the queue or at a higher price (a group with no data yet takes
-- the rate of the group before it, not a coin flip).
local function Level(c, n, parent, k)
  local r, last = {}, 1
  for i = 1, n do
    local sN, eN = c and c[i * 2 - 1] or 0, c and c[i * 2] or 0
    local prior = parent and parent[i] or (i == 1 and 0.5 or last)
    local x = (sN + prior * k) / (sN + eN + k)
    if x > last then x = last end
    r[i], last = x, x
  end
  return r
end
local function Chain(tbl, n, itemC, tier, kind)
  local rAll = Level(tbl.all, n, nil, 2)
  local rTier = Level(tbl["t" .. tier], n, rAll, 30)
  local kc = kind and tbl[kind]
  local rKind = Level(kc, n, rTier, 15)
  return Level(itemC, n, rKind, 4), rKind, kc
end
local function Count(c, i) return c and ((c[i * 2 - 1] or 0) + (c[i * 2] or 0)) or 0 end
local function Logit(p) p = math.max(0.01, math.min(0.99, p)); return math.log(p / (1 - p)) end
local function Unlogit(x) return 1 / (1 + math.exp(-x)) end

-- Chance one listing sells, at unit price `unit` with `ahead` units cheaper,
-- from the feed. Returns p, listings of this item it rests on, and details.
function S.Through(itemID, w, e, unit, ahead)
  local watched = FeedWatched(w)
  if watched <= 0 then return nil end
  local P = Pools(w)
  if P.n < 50 then return nil end
  local tier, kind = Tier(e.spd), Kind(itemID)
  local kk = kind and (kind .. "/" .. tier)
  local qi = 1
  if ahead and ahead > 0 then
    local d = ahead / math.max(e.spd or 0, 0.2)
    qi = d < 0.25 and 2 or d < 1 and 3 or d < 3 and 4 or d < 10 and 5 or 6
  end
  local r = unit / math.max(1, e.avg or e.m or e.p or unit)
  local pi = P_N
  for i, lim in ipairs(P_LIMITS) do if r <= lim then pi = i break end end
  local rQ, rQk, kq = Chain(P.q, Q_N, e.stQ, tier, kk)
  local rP = Chain(P.p, P_N, e.stP, tier, kk)
  local pQ, nQ, pQk, nQk = rQ[qi], Count(e.stQ, qi), rQk[qi], Count(kq, qi)
  local pP, nP = rP[pi], Count(e.stP, pi)
  -- the item's rate at the usual price, to see how much its price group differs
  local base = rP[3]
  -- place in the queue counts in full, price as a correction (they overlap)
  local p = Unlogit(Logit(pQ) + 0.5 * (Logit(pP) - Logit(base)))
  return math.max(0.02, math.min(0.98, p)), (nQ + 0.5 * nP) * watched, {
    queue = qi, price = pi, pQueue = pQ, pPrice = pP, nQueue = nQ, nPrice = nP, kindRate = pQk, kindN = nQk,
    kind = S.KindName(itemID), tier = tier, watched = watched }
end

-- Busiest buying hours at this AH (your PC's clock), from the feed
function S.PeakHours(w)
  local I = ns.Feed and ns.Feed.Info and ns.Feed.Info[w]
  local h = I and I.hours
  if not (h and #h == 24) then return nil end
  local tot = 0
  for i = 1, 24 do tot = tot + (h[i] or 0) end
  if tot < 200 then return nil end
  -- the 4-hour stretch with the most sales
  local best, bi = -1, 1
  for i = 1, 24 do
    local s = 0
    for j = 0, 3 do s = s + (h[((i - 1 + j) % 24) + 1] or 0) end
    if s > best then best, bi = s, i end
  end
  local function H(x) x = x % 24; return (x == 0 and "12 AM") or (x < 12 and (x .. " AM")) or (x == 12 and "12 PM") or ((x - 12) .. " PM") end
  return ("%s-%s"):format(H(bi - 1), H(bi + 3)), best / tot
end

-- Value of putting it up now: relist until sold (up to TRIES), else vendor.
local function ExpectedValue(price, cut, deposit, p, vendor)
  local ev, miss = 0, 1
  for _ = 1, TRIES do
    ev = ev + miss * (p * price * (1 - cut) - (1 - p) * deposit)
    miss = miss * (1 - p)
  end
  return ev + miss * vendor
end

---------------------------------------------------------------------------
-- Self-calibration: the more data comes in, the more the estimates are
-- corrected by what really happened.
--  1. The demand model (MarketChance) against the feed's real sell-through
--     for every item at the AH: how often listings it rated x% really sold.
--  2. Every sell chance AskAH gave when you posted something, against what
--     came back by mail (sold or expired).
-- Both are worked out again every 10 minutes from the saved data.
---------------------------------------------------------------------------
local BINS = 10
local function Bin(p) return math.max(1, math.min(BINS, math.floor(p * BINS) + 1)) end
-- smoothed rate per bin, pulled toward the bin's own prediction while it has
-- few observations, and kept rising from bin to bin
local function Table(sumP, sumY, n, k)
  local t, last = { n = 0, pred = {}, act = {}, cnt = {} }, 0
  for i = 1, BINS do
    local mid = n[i] > 0 and (sumP[i] / n[i]) or ((i - 0.5) / BINS)
    local r = (sumY[i] + mid * k) / (n[i] + k)
    if r < last then r = last end
    t[i], last = r, r
    -- how far off this bin's predictions were, on average (smoothed)
    t.pred[i], t.cnt[i] = mid, n[i]
    t.act[i] = n[i] > 0 and (sumY[i] / n[i]) or nil
    t.n = t.n + n[i]
  end
  return t
end

local calMarket, calMarketT = nil, 0
local function MarketCalibration()
  if calMarket and time() - calMarketT < 600 then return calMarket end
  local sumP, sumY, n = {}, {}, {}
  for i = 1, BINS do sumP[i], sumY[i], n[i] = 0, 0, 0 end
  for _, w in ipairs({ "faction", "neutral" }) do
    for _, e in pairs(ns.Data.Prices(w) or {}) do
      local nT = (e.stSN or 0) + (e.stEN or 0)
      -- only items watched for two days or more: listings last up to 48h,
      -- so before that the feed sees the sales but not yet the expiries
      if nT >= 3 and e.spd and (e.spdN or 0) >= 48 then
        local pm = MarketChance(e.spd, e.q, 1, e.spdN)
        local b = Bin(pm)
        sumP[b], sumY[b], n[b] = sumP[b] + pm * nT, sumY[b] + (e.stSN or 0), n[b] + nT
      end
    end
  end
  calMarket, calMarketT = Table(sumP, sumY, n, 20), time()
  return calMarket
end

-- Your predictions: saved when you post (S.RecordPrediction), matched with
-- the sale / "Auction expired" mail for the same item and AH within 3 days.
local function Preds()
  AskAHDB.preds = AskAHDB.preds or {}
  return AskAHDB.preds
end

function S.RecordPrediction(itemID, ah, count, unit, dep)
  if not (AskAHDB and itemID) then return end
  local a = S.Advise(itemID, count or 1, true)
  local x = a and a.ah[ah or "faction"]
  if not x then return end
  local list = Preds()
  table.insert(list, 1, { v = 2, t = time(), id = itemID, ah = ah or "faction", p = x.raw or x.chance, pm = x.marketChance,
                          pt = x.through, q = count or 1, unit = unit or (x.price and math.floor(x.price / (count or 1))),
                          dep = dep or x.deposit })
  for i = #list, 2001, -1 do list[i] = nil end
end

local function Resolved()
  local outs = {}
  for _, c in pairs(AskAHDB and AskAHDB.chars or {}) do
    for _, e in ipairs(c.sales or {}) do
      if e.id and e.t and (not e.kind or e.kind == "expired") then
        local k = e.id .. ":" .. ((e.ah == "neutral") and "neutral" or "faction")
        outs[k] = outs[k] or {}
        table.insert(outs[k], { t = e.t, y = e.kind and 0 or 1 })
      end
    end
  end
  for _, l in pairs(outs) do table.sort(l, function(a, b) return a.t < b.t end) end
  local res, used = {}, {}
  local preds = Preds()
  for i = #preds, 1, -1 do -- oldest first
    local pr = preds[i]
    local l = outs[pr.id .. ":" .. pr.ah]
    for _, o in ipairs(l or {}) do
      if not used[o] and o.t >= pr.t - 300 and o.t <= pr.t + 3 * 86400 then
        used[o] = true
        pr.y = o.y
        res[#res + 1] = { p = pr.p, pm = pr.pm, pt = pr.pt, y = o.y, v = pr.v }
        break
      end
    end
  end
  return res
end

local calYou, calYouT = nil, 0
local function YourCalibration()
  if calYou and time() - calYouT < 600 then return calYou end
  local sumP, sumY, n = {}, {}, {}
  for i = 1, BINS do sumP[i], sumY[i], n[i] = 0, 0, 0 end
  local res = Resolved()
  -- only chances from the current model (0.12+) correct it; older ones came
  -- from the feed that missed most sales
  for _, r in ipairs(res) do
    if r.p and (r.v or 1) >= 2 then local b = Bin(r.p); sumP[b], sumY[b], n[b] = sumP[b] + r.p, sumY[b] + r.y, n[b] + 1 end
  end
  calYou, calYouT = Table(sumP, sumY, n, 8), time()
  calYou.res = res
  return calYou
end

-- shift p by how far off predictions like it were (its bin's smoothed rate
-- minus the bin's average prediction), at most 0.2 either way
local function Adjust(t, p, minN)
  if not (t and p) or t.n < minN then return p end
  local b = Bin(p)
  local d = t[b] - (t.pred[b] or p)
  return math.max(0.01, math.min(0.99, p + math.max(-0.2, math.min(0.2, d))))
end

-- /askah losses: what selling has cost you, per AH and per item: the AH cut,
-- deposits lost on auctions that expired, and what didn't sell where.
function S.Losses(days)
  local P, Money = ns.Print, ns.Data.Money
  local since = days and (time() - days * 86400) or 0
  local deps = DepositRates()
  local tot = { faction = {}, neutral = {} }
  local items = {}
  local realDep = {} -- deposits you really paid, by item:ah, from your posts
  for _, pr in ipairs(AskAHDB and AskAHDB.preds or {}) do
    if pr.y == 0 and pr.dep and pr.t >= since then
      local k = pr.id .. ":" .. pr.ah
      realDep[k] = realDep[k] or {}
      table.insert(realDep[k], pr.dep)
    end
  end
  for _, c in pairs(AskAHDB and AskAHDB.chars or {}) do
    for _, e in ipairs(c.sales or {}) do
      if (e.t or 0) >= since and e.id and (not e.kind or e.kind == "expired") then
        local w = (e.ah == "neutral") and "neutral" or "faction"
        local t = tot[w]
        local it = items[e.id .. ":" .. w] or { id = e.id, n = e.n, w = w, sold = 0, unsold = 0, lost = 0, cut = 0, got = 0 }
        items[e.id .. ":" .. w] = it
        if e.kind == "expired" then
          local k = e.id .. ":" .. w
          local d = realDep[k] and table.remove(realDep[k], 1)
          d = d or math.floor(S.Vendor(e.id) * (e.q or 1) * deps[w])
          t.unsold, t.lost = (t.unsold or 0) + 1, (t.lost or 0) + d
          it.unsold, it.lost = it.unsold + 1, it.lost + d
        else
          t.sold, t.cut, t.got = (t.sold or 0) + 1, (t.cut or 0) + (e.cut or 0), (t.got or 0) + (e.got or 0)
          it.sold, it.cut, it.got = it.sold + 1, it.cut + (e.cut or 0), it.got + (e.got or 0)
        end
      end
    end
  end
  P(("what selling cost you%s (deposits on expired auctions are what you paid where AskAH saw you post, else estimated):"):format(days and (" in the last " .. days .. " days") or ""))
  for _, w in ipairs({ "faction", "neutral" }) do
    local t = tot[w]
    local n = (t.sold or 0) + (t.unsold or 0)
    if n > 0 then
      print(("   %s AH: %d sold, %d didn't (%d%% sold). Got %s after a %s cut; lost %s in deposits. Net %s."):format(
        w == "neutral" and "Neutral" or "Faction", t.sold or 0, t.unsold or 0, math.floor((t.sold or 0) / n * 100 + 0.5),
        Money(t.got or 0), Money(t.cut or 0), Money(t.lost or 0), Money(math.max(0, (t.got or 0) - (t.lost or 0)))))
    end
  end
  local list = {}
  for _, it in pairs(items) do if it.unsold > 0 then list[#list + 1] = it end end
  table.sort(list, function(a, b) return a.lost > b.lost end)
  if #list == 0 then print("   nothing has expired yet (AskAH sees it from the \"Auction expired\" mail).") return end
  print("   biggest losses (didn't sell):")
  for i = 1, math.min(8, #list) do
    local it = list[i]
    local a = S.Advise(it.id, 1)
    local now = a.bestWhere == "vendor" and "vendor it now" or ("now best at the " .. a.bestWhere .. " AH")
    print(("     %s, %s AH: %d of %d didn't sell, %s lost. %s"):format(it.n or ("item " .. it.id), it.w, it.unsold,
      it.sold + it.unsold, Money(it.lost), now))
  end
end

-- /askah accuracy: how well the estimates have matched what happened.
function S.Accuracy()
  local Pr = ns.Print
  Pr("how well the chance to sell matches what really happened (per listing, before it runs out):")
  for _, w in ipairs({ "faction", "neutral" }) do
    local watched, I = FeedWatched(w)
    local P = Pools(w)
    if I then
      print(("   %s AH: the Blizzard feed has followed %d listings to the end%s."):format(w == "neutral" and "Neutral" or "Faction",
        math.floor(P.n + 0.5), watched < 1 and (", still warming up (" .. math.floor(watched * 100 + 0.5) .. "%)") or ""))
      local c = S.FeedCalibration and S.FeedCalibration(w)
      if c and c.n > 0 then
        local parts = {}
        for i = 1, BINS do
          if (c.cnt[i] or 0) >= 20 then
            parts[#parts + 1] = ("said %d-%d%%: %d%% sold"):format((i - 1) * 10, i * 10, math.floor(c.act[i] * 100 + 0.5))
          end
        end
        if #parts > 0 then print("     before correction, " .. table.concat(parts, "; ")) end
        print("     each band's error is taken off the chances you see.")
      end
      local all = P.q.all
      if all and watched > 0 then
        local b = {}
        for i = 1, Q_N do
          local sN, eN = all[i * 2 - 1], all[i * 2]
          if sN + eN >= 5 then b[#b + 1] = ("%s %d%%"):format(Q_NAMES[i], math.floor(sN / (sN + eN) * 100 + 0.5)) end
        end
        if #b > 0 then print("     listings sold when " .. table.concat(b, "; ")) end
      end
    end
  end
  local y = YourCalibration()
  local res = y.res or {}
  local function score(v2)
    local list = {}
    for _, r in ipairs(res) do if ((r.v or 1) >= 2) == v2 then list[#list + 1] = r end end
    if #list == 0 then return nil end
    local brier, base, sold = 0, 0, 0
    for _, r in ipairs(list) do sold = sold + r.y end
    local rate = sold / #list
    for _, r in ipairs(list) do brier = brier + (r.p - r.y) ^ 2; base = base + (rate - r.y) ^ 2 end
    return #list, sold, rate, brier / #list, base / #list
  end
  local n, sold, rate, b, base = score(true)
  if n then
    print(("   your own posts since this update: %d settled, %d sold (%d%%). Error score %.3f vs %.3f for always guessing %d%% (lower is better)."):format(
      n, sold, math.floor(rate * 100 + 0.5), b, base, math.floor(rate * 100 + 0.5)))
    print("   AskAH also corrects its chances with these once there are 10+ (now " .. n .. ").")
  else
    print("   your own posts since this update: none settled yet (the sale or expired mail settles each one).")
  end
  local n0, _, _, b0, base0 = score(false)
  if n0 then print(("   (older posts, from before the feed fix: %d, error %.3f vs %.3f; not used.)"):format(n0, b0, base0)) end
end

---------------------------------------------------------------------------
-- The market part of the chance: demand vs competition and the feed's
-- sell-through for a listing at `unit` with `ahead` units cheaper. Then
-- checked against what really happened: for every item the feed followed,
-- the chance this gives for its cheapest listing against how often its
-- cheapest listings really sold, by 10% band; each band's average error is
-- taken off (FeedCalibration, worked out every 30 min).
---------------------------------------------------------------------------
local function MarketPart(itemID, w, e, unit, ahead, count)
  local pm = MarketChance(e.spd, e.q, count or 1, e.spdN)
  pm = Adjust(MarketCalibration(), pm, 200)
  local pt, nT, why = S.Through(itemID, w, e, unit, ahead)
  local watched = FeedWatched(w)
  -- demand estimate counts as 2 listings; feed sell-through as 3 (items like
  -- it) plus this item's own listings, up to 25
  local wM = pm and 2 or 0
  local wT = pt and (3 * watched + math.min(nT or 0, 25)) or 0
  if wM + wT <= 0 then return nil, 0, pt, nT or 0, why, pm end
  return ((pm or 0) * wM + (pt or 0) * wT) / (wM + wT), wM + wT, pt, nT or 0, why, pm
end

local calFeed, calFeedT = {}, {}
local function FeedCalibration(w)
  if calFeed[w] and time() - (calFeedT[w] or 0) < 1800 then return calFeed[w] end
  local sumP, sumY, n = {}, {}, {}
  for i = 1, BINS do sumP[i], sumY[i], n[i] = 0, 0, 0 end
  for id, e in pairs(ns.Data.Prices(w) or {}) do
    local q = e.stQ
    local k = q and (q[1] + q[2]) or 0
    if k >= 1 and e.p and e.p > 0 then
      local p = MarketPart(id, w, e, math.max(1, math.floor(e.p * 0.99)), 0, 1)
      if p then
        local b = Bin(p)
        sumP[b], sumY[b], n[b] = sumP[b] + p * k, sumY[b] + q[1], n[b] + k
      end
    end
  end
  calFeed[w], calFeedT[w] = Table(sumP, sumY, n, 30), time()
  return calFeed[w]
end
S.FeedCalibration = FeedCalibration
local function Calibrated(w, p)
  if not p then return nil end
  return Adjust(FeedCalibration(w), p, 300)
end

-- Returns { vendor, bestWhere = "faction"|"neutral"|"vendor", best = value,
--           ah = { faction = {...}, neutral = {...} }, reason }
-- at = { w = "faction"|"neutral", unit = price each, ahead = units cheaper }:
-- the chance for a listing you already have up (Sales.lua), at that AH only.
function S.Advise(itemID, count, raw, at)
  count = count or 1
  local vendor = S.Vendor(itemID) * count
  local deps = DepositRates()
  local hist = History(itemID)
  local tsm = S.TSMData(itemID)
  local out = { vendor = vendor, ah = {}, bestWhere = vendor > 0 and "vendor" or nil, best = vendor }
  for _, w in ipairs(at and { at.w } or { "faction", "neutral" }) do
    local e = ns.Data.Prices(w)[itemID]
    -- no AskAH price: Auctionator's scan, then TSM's market value (faction AH only)
    if not (e and e.p and e.p > 0) and w == "faction" then
      local alt = S.AuctionatorPrice(itemID) or (tsm and (tsm.market or tsm.region))
      if alt and alt > 0 then e = { p = alt, alt = true } end
    end
    if e and e.p and e.p > 0 then
      local price = math.max(1, math.floor(e.p * 0.99)) * count   -- undercut the cheapest a little
      if at and at.unit then price = math.max(1, math.floor(at.unit)) * count end
      local deposit = math.floor(vendor * deps[w])
      local h = hist[w]
      -- 1. the market: demand vs competition, and the feed's sell-through for
      -- listings like yours (the cheapest, at this price against usual), this
      -- item first, then items like it; checked against what really sold
      local pB, wB, pt, nT, why, pm = MarketPart(itemID, w, e, price / count, at and at.ahead or 0, count)
      pB = Calibrated(w, pB)
      local pFar
      if pt and e.avg and e.avg > 0 and not at then pFar = Calibrated(w, (MarketPart(itemID, w, e, e.avg, math.max(1, e.spd or 1), count))) end
      local watched = FeedWatched(w)
      -- 2. your own sales / expiries of it here: each counts as 2 listings
      -- (your listings are the most like yours)
      local wY = 2 * (h.sold + h.unsold)
      -- TSM's region-wide sale rate (thousands of auctions, but other realms
      -- and prices): counts as 3 observations
      local pR = tsm and tsm.rate and tsm.rate > 0 and math.min(0.97, tsm.rate) or nil
      local wR = pR and 3 or 0
      -- you've had this expire here at this price or less: listing at the
      -- same price again counts as one more "didn't sell"
      local failPenalty = (h.failUnit and count > 0 and price / count >= h.failUnit) and 2 or 0
      local W = wB + wY + wR + failPenalty
      local p
      if W > 0 then
        p = ((pB or 0) * wB + 2 * h.sold + (pR or 0) * wR) / W
      else
        p = 0.5
      end
      -- nothing of this sold anywhere we've looked: the cheapest listing's
      -- price is untested. If it's far above the other AH's price, or far
      -- above anything a vendor-priced item like it goes for, lower the chance.
      local untested, capped
      local noSales = (e.spd or 0) < 0.05 and nT < 1 and h.sold == 0 and not pR
      if noSales and count > 0 and not at then
        local unit = price / count
        local o = ns.Data.Prices(w == "faction" and "neutral" or "faction")[itemID]
        local ref = o and o.p and o.p > 0 and o.p or nil
        local other = OtherHouseMin(itemID, e.p)
        if other and (not ref or other < ref) then ref = other end
        -- a lone listing far above every other AH isn't a price to undercut:
        -- suggest 1.5x the cheapest elsewhere instead
        -- (only when few are listed: a dozen sellers agreeing on a price is a market)
        local thin = (e.q or 0) <= 3
        if thin and ref and unit > 2 * ref then
          capped = true
          price = math.max(1, math.floor(ref * 1.5)) * count
          unit = price / count
        elseif thin and not ref and vendor > 0 and unit > 30 * (vendor / count) then
          -- the only listing anywhere, untested: count it at 30x vendor at most
          capped = true
          price = math.floor(30 * vendor)
          unit = price / count
        end
        local f = 1
        if ref and unit > 2 * ref then f = math.sqrt(2 * ref / unit) end
        local v1 = vendor / count
        if v1 > 0 and unit > 30 * v1 then f = math.min(f, math.sqrt(30 * v1 / unit)) end
        p = p * math.max(0.25, f)
        if f < 1 then untested = true end
      end
      p = math.max(0.02, math.min(0.98, p))
      local rawP = p
      -- corrected by how your own posts with this chance really did
      if not raw then p = math.max(0.02, math.min(0.98, Adjust(YourCalibration(), p, 10))) end
      local conf = W >= 14 and "high" or (W >= 5 and "medium" or "low")
      if watched < 1 and conf == "high" and wY < 12 then conf = "medium" end
      local ev = ExpectedValue(price, CUT[w], deposit, p, vendor)
      out.ah[w] = { price = price, deposit = deposit, chance = p, raw = rawP, conf = conf, marketChance = pm, through = pt,
                    throughN = nT, throughFar = pFar, why = why, spd = e.spd, spdN = e.spdN, listed = e.q,
                    sold = h.sold, unsold = h.unsold, value = ev, net = math.floor(price * (1 - CUT[w])),
                    lost = h.lost, lostEst = (h.lostN or 0) > 0 and math.floor((h.lostN or 0) * S.Vendor(itemID) * deps[w]) or 0,
                    failUnit = h.failUnit, tsmRate = pR, altPrice = e.alt, untested = untested, watched = watched, capped = capped,
                    age = e.t and (time() - e.t) or nil }
      if ev > out.best + 1 then out.best, out.bestWhere = ev, w end
    end
  end
  -- close call: the vendor is instant and certain
  if out.bestWhere ~= "vendor" and vendor > 0 and out.best < vendor * 1.1 + 20 then
    out.closeCall = true
    out.bestWhere, out.best = "vendor", vendor
  end
  return out
end

local function Pct(p) return ("%d%%"):format(math.floor(p * 100 + 0.5)) end

-- Tooltip lines: one verdict plus one line per auction house.
function S.Lines(itemID, count, bound)
  local Money = ns.Data.Money
  local GREEN, YELLOW, GREY = "|cff33ff33", "|cffffd200", "|cff999999"
  local a = S.Advise(itemID, count)
  local lines = {}
  if bound then
    lines[1] = a.vendor > 0 and (YELLOW .. "Soulbound: vendor it for " .. Money(a.vendor) .. ".|r") or (GREY .. "Soulbound, no vendor value.|r")
    return lines, a
  end
  if not next(a.ah) then return nil, a end
  for _, w in ipairs({ "faction", "neutral" }) do
    local x = a.ah[w]
    if x then
      local why = {}
      if x.spd and x.spd < 0.05 then why[#why + 1] = ("none sold in the ~%dh watched"):format(math.floor((x.spdN or 24) + 0.5))
      elseif x.spd then why[#why + 1] = ("sells ~%s/day"):format(x.spd >= 10 and ("%d"):format(x.spd) or ("%.1f"):format(x.spd)) end
      if x.listed then why[#why + 1] = ("%d listed"):format(x.listed) end
      if x.through and x.why then
        if x.throughN >= 3 then
          why[#why + 1] = ("%s of its cheapest listings sell (%d watched)"):format(Pct(x.why.pQueue), math.floor(x.why.nQueue + 0.5))
        elseif x.why.kind and x.why.kindN and x.why.kindN >= 5 then
          why[#why + 1] = ("items like it (%s, %s): %s sell when cheapest"):format(x.why.kind, TIER_NAMES[x.why.tier], Pct(x.why.kindRate))
        end
        if x.why.price ~= 3 then why[#why + 1] = ("listing at %s"):format(P_NAMES[x.why.price]) end
      end
      if x.sold + x.unsold > 0 then why[#why + 1] = ("you sold %d of %d"):format(x.sold, x.sold + x.unsold) end
      if x.tsmRate then why[#why + 1] = ("TSM region sale rate %s"):format(Pct(x.tsmRate)) end
      if x.altPrice then why[#why + 1] = "price from Auctionator/TSM" end
      if x.capped then why[#why + 1] = "the lowest here is far above other AHs, so priced from theirs" end
      if x.untested then why[#why + 1] = "nobody's bought at this price yet" end
      if #why == 0 then why[1] = "no sales data yet" end
      local col = x.chance >= 0.7 and GREEN or (x.chance >= 0.35 and YELLOW or "|cffff6060")
      lines[#lines + 1] = ("%s AH: %s%s chance to sell|r %s(each listing, before it runs out; %s confidence)|r"):format(w == "neutral" and "Neutral" or "Faction",
        col, Pct(x.chance), GREY, x.conf)
      lines[#lines + 1] = GREY .. "  " .. table.concat(why, ", ") .. "|r"
      if x.throughFar then lines[#lines + 1] = GREY .. ("  at the usual price, behind a day of cheaper ones: ~%s|r"):format(Pct(x.throughFar)) end
      local peak = S.PeakHours(w)
      if peak then lines[#lines + 1] = GREY .. ("  most buying here %s (your clock)|r"):format(peak) end
      local lost = (x.lost or 0) + (x.lostEst or 0)
      if x.unsold > 0 then
        lines[#lines + 1] = "|cffff6060" .. ("  didn't sell here %d time%s, ~%s lost in deposits%s|r"):format(x.unsold, x.unsold == 1 and "" or "s",
          Money(lost), x.failUnit and (", expired at " .. Money(x.failUnit) .. " each") or "")
      end
      lines[#lines + 1] = GREY .. ("  worth ~%s per listing after the cut and lost deposits|r"):format(Money(math.max(0, math.floor(x.value))))
    end
  end
  local v
  if not a.bestWhere or not (a.bestWhere == "vendor" or a.ah[a.bestWhere]) then
    v = GREY .. "Hardly worth anything here: no vendor price, and it's unlikely to sell at the AH.|r"
  elseif a.bestWhere == "vendor" then
    v = a.closeCall and (YELLOW .. ("Vendor it: %s now beats the AH's ~%s once the risk of not selling counts.|r"):format(Money(a.vendor), Money(math.floor(math.max(a.ah.faction and a.ah.faction.value or 0, a.ah.neutral and a.ah.neutral.value or 0)))))
                     or (YELLOW .. ("Vendor it: %s.|r"):format(Money(a.vendor)))
  else
    local x = a.ah[a.bestWhere]
    v = GREEN .. ("Auction it at the %s AH: list ~%s, expect ~%s (+%s over vendor).|r"):format(
      a.bestWhere, Money(x.price), Money(math.floor(x.value)), Money(math.floor(x.value - a.vendor)))
  end
  table.insert(lines, 1, v)
  return lines, a
end
