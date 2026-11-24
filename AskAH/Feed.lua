-- Feed.lua
-- Hourly auction house data from Blizzard's web API, fetched outside the game
-- by Feed\AskAHFeed.ps1 (run hourly by Windows Task Scheduler) and written to
-- FeedData.lua as the global AskAHFeed. On login (or /reload) AskAH merges it
-- into its prices, sell rates and deals, so you don't have to stand at the AH.
--
-- WoW Forever has no realms: auction houses are shared per ruleset. The API
-- lists 15 houses in 5 groups of three (Alliance, Horde, Blackwater) and does
-- not say which group is which ruleset, so AskAH works it out by comparing
-- each house with the prices you've scanned yourself, and remembers the group
-- in AskAHDB.feedGroup (the fetcher reads that back and from then on only
-- downloads your three houses). /askah feed group <1-5> sets it by hand.
local _, ns = ...
local F = {}
ns.Feed = F

-- house id -> group, kind (from the community-mapped API house list)
local HOUSES = {
  [110] = { 1, "alliance" }, [113] = { 1, "horde" }, [116] = { 1, "blackwater" },
  [111] = { 2, "alliance" }, [114] = { 2, "horde" }, [117] = { 2, "blackwater" },
  [112] = { 3, "alliance" }, [115] = { 3, "horde" }, [118] = { 3, "blackwater" },
  [119] = { 4, "alliance" }, [120] = { 4, "horde" }, [121] = { 4, "blackwater" },
  [123] = { 5, "alliance" }, [124] = { 5, "horde" }, [125] = { 5, "blackwater" },
}
F.HOUSES = HOUSES

local function MyKind() return UnitFactionGroup("player") == "Horde" and "horde" or "alliance" end

-- "min,market,qty,avg,seen,prevAvg,prevSeen,qa,spd,spdN,sN,eN,sF,eF;queue;price|u:c,u:c,..."
-- queue / price: sold/expired pairs ("s/e", or "0") by place in the queue
-- (6 groups) and by price against the usual price (7 groups).
local function Pairs(str, n)
  local t, i = {}, 0
  for x in (str or ""):gmatch("[^,]+") do
    local a, b = x:match("^([%d%.]+)/([%d%.]+)$")
    t[i * 2 + 1], t[i * 2 + 2] = tonumber(a) or 0, tonumber(b) or 0
    i = i + 1
  end
  if i < n then return nil end
  return t
end
local function Parse(s)
  local head, rows = s:match("^([^|]*)|?(.*)$")
  local nums, queue, price = head:match("^([^;]*);?([^;]*);?(.*)$")
  local v = {}
  for x in nums:gmatch("[^,]+") do v[#v + 1] = tonumber(x) end
  v.queue, v.price = Pairs(queue, 6), Pairs(price, 7)
  local r = {}
  if rows and rows ~= "" then
    for u, c in rows:gmatch("(%d+):(%d+)") do r[#r + 1] = { tonumber(u), tonumber(c) } end
  end
  return v, r
end

function F.Available() return type(AskAHFeed) == "table" and type(AskAHFeed.houses) == "table" end

-- How well a feed house matches the prices you scanned yourself (0..1), and
-- how many items could be compared.
local function Score(h, which)
  local mine = ns.Data.Prices(which)
  local n, good = 0, 0
  for id, s in pairs(h.items or {}) do
    local e = mine[id]
    if e and e.m and e.m > 0 and e.t and time() - e.t < 30 * 86400 then
      local v = Parse(s)
      local m = v[2]
      if m and m > 0 then
        n = n + 1
        local r = m / e.m
        if r > 0.67 and r < 1.5 then good = good + 1 end
      end
    end
  end
  return n > 0 and good / n or 0, n
end

-- Pick the group whose houses look most like what you've scanned.
function F.Detect(verbose)
  if not F.Available() then return nil end
  local best, bestScore, report = nil, 0, {}
  local kind = MyKind()
  for id, h in pairs(AskAHFeed.houses) do
    local info = HOUSES[id]
    if info and (info[2] == kind or info[2] == "blackwater") then
      local sc, n = Score(h, info[2] == "blackwater" and "neutral" or "faction")
      report[#report + 1] = ("group %d %s house %d: %d%% of %d items match"):format(info[1], info[2], id, sc * 100, n)
      if n >= 15 and sc > bestScore then best, bestScore = info[1], sc end
    end
  end
  if verbose then for _, l in ipairs(report) do print("   " .. l) end end
  if best and bestScore >= 0.5 then return best end
  return nil
end

-- Merge one house into AskAH's prices and work out its deals.
-- About each of your houses: sales by hour of day, since when listings are
-- timed, which listing lengths the fetcher has learned (SellAdvice uses it).
F.Info = {}
local function ApplyHouse(id, h, which, dealsOnly)
  local key = ns.Data.KeyFor(which)
  F.Info[which] = { t = h.t, hours = h.hours, since = h.since, durations = h.durations, hasTL = h.hasTL }
  AskAHDB.feedApplied = AskAHDB.feedApplied or {}
  if not dealsOnly and (AskAHDB.feedApplied[key] or 0) >= (h.t or 0) then return false end
  local prices = ns.Data.Prices(which)
  local scanned = {}
  for itemID, s in pairs(h.items or {}) do
    local v, rows = Parse(s)
    local e = prices[itemID]
    if not e then e = {}; prices[itemID] = e end
    if not dealsOnly then
      if (e.t or 0) <= h.t or not e.p then e.p, e.m, e.q, e.t = v[1], v[2], v[3], math.max(e.t or 0, h.t) end
      -- history: the feed sees the AH every hour, so it usually knows more
      if v[5] and v[5] >= (e.seen or 0) then
        e.avg, e.seen, e.prevSeen, e.qa = v[4], v[5], v[7], v[8]
        e.prevAvg = (v[6] and v[6] > 0) and v[6] or nil
      end
      if v[10] and v[10] >= 1 then e.spd, e.spdN, e.spdT = v[9], v[10], h.t end
      -- sell-through: listings sold / expired, near the lowest price and above it
      if v[11] then e.stSN, e.stEN, e.stSF, e.stEF, e.stT = v[11], v[12], v[13], v[14], h.t end
      -- by place in the queue and by price (newer fetcher only)
      e.stQ, e.stP = v.queue, v.price
      e.feed = h.t
    end
    if #rows > 0 then scanned[itemID] = rows end
  end
  if ns.Deals and ns.Deals.FromScan then
    pcall(ns.Deals.FromScan, scanned, key, which == "neutral", h.t, "feed")
  end
  AskAHDB.feedApplied[key] = h.t
  return true
end

-- Your realm's ruleset is in its name; checked against the API: US "RP PvP"
-- realms are group 5, PvP realms group 1. Others fall back to price matching.
function F.GroupFromRealm()
  local realm = GetRealmName() or ""
  if realm:find("RP[ %-]?PvP") or realm:find("rp[ %-]?pvp") then
    if (AskAHFeed and AskAHFeed.region) == "us" then return 5 end
  elseif realm:find("PvP") or realm:find("PVP") then
    return 1
  end
end

function F.Apply(dealsOnly)
  if not F.Available() or not AskAHDB then return end
  local group = AskAHDB.feedGroup or AskAHFeed.group
  if not group then
    group = F.GroupFromRealm() or F.Detect()
    if group then
      AskAHDB.feedGroup = group
      ns.Print(("Blizzard AH data: your auction houses are group %d. The fetcher will download only those from now on."):format(group))
    else
      if not dealsOnly then
        ns.Print("Blizzard AH data is here, but AskAH can't tell yet which auction houses are yours. Set it with /askah feed group <1-5> (see /askah feed for how well each matches your prices).")
      end
      return
    end
  end
  local kind, applied = MyKind(), 0
  for id, h in pairs(AskAHFeed.houses) do
    local info = HOUSES[id]
    if info and info[1] == group and h.full then
      local which = (info[2] == "blackwater" and "neutral") or (info[2] == kind and "faction") or nil
      if which and ApplyHouse(id, h, which, dealsOnly) then applied = applied + 1 end
    end
  end
  if applied > 0 and not dealsOnly then
    ns.Print(("Blizzard AH data from %s loaded: prices, sell rates and deals updated."):format(ns.Data.Ago(AskAHFeed.t)))
  end
  if ns.Deals and ns.Deals.QueueRefresh then ns.Deals.QueueRefresh() end
end

function F.Status()
  if not F.Available() then
    ns.Print("no Blizzard AH data yet. See Feed\\README.txt in the AskAH folder to set up the hourly fetcher.")
    return
  end
  local n = 0
  for _ in pairs(AskAHFeed.houses) do n = n + 1 end
  ns.Print(("Blizzard AH data: %s region, fetched %s, %d house(s) in the file, your group: %s"):format(
    tostring(AskAHFeed.region or "?"):upper(), ns.Data.Ago(AskAHFeed.t), n, tostring(AskAHDB.feedGroup or "not known yet")))
  F.Detect(true)
end

function F.Command(rest)
  local v, arg = (rest or ""):lower():match("^(%S*)%s*(.*)$")
  if v == "group" then
    local g = tonumber(arg)
    if g and g >= 1 and g <= 5 then
      AskAHDB.feedGroup = g
      AskAHDB.feedApplied = {}
      ns.Print(("auction house group set to %d. The fetcher picks it up after you /reload or log out; run it again then."):format(g))
      F.Apply()
    elseif arg == "auto" then
      AskAHDB.feedGroup = nil
      AskAHDB.feedApplied = {}
      F.Apply()
    else
      ns.Print("usage: /askah feed group 1-5 (or auto)")
    end
  else
    F.Status()
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  if not (C_Timer and C_Timer.After) then pcall(F.Apply) return end
  -- after login has settled; a second pass once item info (vendor prices) has loaded
  C_Timer.After(8, function() local ok, err = pcall(F.Apply); if not ok then ns.Print("feed error: " .. tostring(err)) end end)
  C_Timer.After(90, function() pcall(F.Apply, true) end)
end)
