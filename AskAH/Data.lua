-- Data.lua
-- Reads live game data through the WoW addon API and saves it in AskAHDB:
--   * Auction house prices (full scan + whatever you search + tooltip line)
--   * Character stats, money, equipped gear
--   * Bags (incl. reagent bag) and bank
--
-- Everything is written to disk on /reload or logout at:
--   WTF\Account\<ACCOUNT>\SavedVariables\AskAH.lua
--
-- The code checks for both the modern auction API (C_AuctionHouse) and the
-- classic-style one (QueryAuctionItems), so it works with whichever one
-- WoW: Forever's client exposes.
local _, ns = ...
local Data = {}
ns.Data = Data

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if ok then return a, b, c, d, e end
  return nil
end

local function NameFromLink(link)
  return link and link:match("%[(.-)%]")
end

local function ItemName(itemID)
  local b = AskAHBlizzAPI and AskAHBlizzAPI.Item(itemID)   -- Blizzard API data first
  if b then return b.name end
  if C_Item and C_Item.GetItemNameByID then
    local n = try(C_Item.GetItemNameByID, itemID)
    if n then return n end
  end
  return (try((C_Item and C_Item.GetItemInfo) or GetItemInfo, itemID))
end

function Data.Money(copper)
  copper = math.floor(copper or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  -- %.0f, not %d: the game's %d stops at ~214,748g (troll listings go higher)
  if g > 0 then return ("%.0fg %ds %dc"):format(g, s, c) end
  if s > 0 then return ("%ds %dc"):format(s, c) end
  return ("%dc"):format(c)
end

function Data.Ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 120 then return "just now" end
  if d < 7200 then return ("%d min ago"):format(d / 60) end
  if d < 172800 then return ("%d h ago"):format(d / 3600) end
  return ("%d days ago"):format(d / 86400)
end

-- Which auction house is open? The goblin (neutral, cross-faction) AHs are in
-- Booty Bay, Gadgetzan and Everlook. There is no API that says "neutral", so
-- we go by where you are (English zone names), with /askah ahtype to force it.
local NEUTRAL_PLACES = {
  ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
  ["Tanaris"] = true, ["Winterspring"] = true,
  ["Stranglethorn Vale"] = true, ["The Cape of Stranglethorn"] = true,
}
local ahIsNeutral = false

function Data.DetectAH()
  local forced = AskAHDB and AskAHDB.ahType
  if forced == "neutral" then ahIsNeutral = true return end
  if forced == "faction" then ahIsNeutral = false return end
  local sub = GetSubZoneText and GetSubZoneText() or ""
  local zone = GetRealZoneText and GetRealZoneText() or ""
  ahIsNeutral = NEUTRAL_PLACES[sub] or NEUTRAL_PLACES[zone] or false
end

function Data.IsNeutralOpen() return ahIsNeutral end

local function FactionKey()
  return (GetRealmName() or "?") .. " - " .. (UnitFactionGroup("player") or "?")
end
local function NeutralKey()
  return (GetRealmName() or "?") .. " - Neutral"
end

-- Key for the AH you're standing at (faction AH when none is open).
local ahOpen = false
function Data.IsAHOpen() return ahOpen end
local scanKey -- AH key locked in while a scan is being processed
local function RealmKey()
  if scanKey then return scanKey end
  if ahOpen and ahIsNeutral then return NeutralKey() end
  return FactionKey()
end
Data.CurrentKey = RealmKey
-- Key for the faction or neutral AH, wherever you are.
function Data.KeyFor(which) return which == "neutral" and NeutralKey() or FactionKey() end

local function CharKey()
  return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- which: "faction", "neutral", or nil for the AH you're at.
function Data.Prices(which)
  AskAHDB.prices = AskAHDB.prices or {}
  local k = (which == "neutral" and NeutralKey()) or (which == "faction" and FactionKey()) or RealmKey()
  AskAHDB.prices[k] = AskAHDB.prices[k] or {}
  return AskAHDB.prices[k]
end

function Data.Char()
  AskAHDB.chars = AskAHDB.chars or {}
  local k = CharKey()
  AskAHDB.chars[k] = AskAHDB.chars[k] or {}
  return AskAHDB.chars[k]
end

-- Record one listing. Keeps the cheapest unit buyout seen in the current pass.
-- During a full scan every listing is also kept (in memory only) so the scan
-- can work out a market price, price history and deals when it finishes.
local scanPass = 0
local scanning = false
local listings -- [itemID] = { unit, count, unit, count, ... } for the running full scan
local function Record(itemID, name, count, buyout, pass, owner)
  if not itemID or not buyout or buyout <= 0 then return end
  count = (count and count > 0) and count or 1
  local unit = buyout / count
  local p = Data.Prices()
  local e = p[itemID]
  if not e or e.pass ~= pass then
    e = e or {}
    e.n, e.p, e.q, e.t, e.pass = name or e.n, unit, count, time(), pass
    p[itemID] = e
  else
    if unit < e.p then e.p = unit end
    e.q = e.q + count
    e.t = time()
    if name and not e.n then e.n = name end
  end
  if listings and pass == scanPass and not (owner and owner == UnitName("player")) then
    local l = listings[itemID]
    if not l then l = {}; listings[itemID] = l end
    l[#l + 1] = unit
    l[#l + 1] = count
  end
end

-- How fast an item sells at this AH. Each full scan keeps a fingerprint of the
-- cheapest 40 listings (unit price + stack size). On the next scan (5 min to
-- 6 h later) listings from the fingerprint that are gone were mostly bought:
-- auctions last 12-48 h, so we take off the share that would have expired.
-- Cancelled undercuts also count as gone, so treat it as an estimate.
-- Saves e.spd = units sold per day (running average) and e.spdN = measurements.
local SoldSince
local SNAP_MAX, GAP_MIN, GAP_MAX, LIFE = 40, 5 * 60, 6 * 3600, 24 * 3600
SoldSince = function(e, rows)
  local now = time()
  -- Too soon after the last look: keep the older snapshot, or repeated
  -- searches a minute apart would keep resetting the clock.
  if e.snap and e.snapT and now - e.snapT < GAP_MIN then return end
  if e.snap and e.snapT then
    local gap = now - e.snapT
    if gap >= GAP_MIN and gap <= GAP_MAX then
      local cur = {}
      for _, r in ipairs(rows) do
        local k = math.floor(r[1]) .. ":" .. r[2]
        cur[k] = (cur[k] or 0) + 1
      end
      local gone, before = 0, 0
      for p, c in e.snap:gmatch("(%d+):(%d+)") do
        local k = p .. ":" .. c
        c = tonumber(c)
        before = before + c
        if (cur[k] or 0) > 0 then cur[k] = cur[k] - 1 else gone = gone + c end
      end
      local sold = math.max(0, gone - before * gap / LIFE)
      local perDay = sold * 86400 / gap
      e.spd = e.spd and (e.spd * 0.6 + perDay * 0.4) or perDay
      e.spdN = (e.spdN or 0) + 1
      e.spdT = now
    end
  end
  local parts = {}
  for i = 1, math.min(#rows, SNAP_MAX) do parts[i] = math.floor(rows[i][1]) .. ":" .. rows[i][2] end
  e.snap, e.snapT = table.concat(parts, ","), now
end

-- Market price of one scan: the price at the cheapest quarter of the units
-- listed (like TSM's market value, it ignores the single cheapest listing and
-- the overpriced tail). Updates the item's usual price (a running average over
-- scans), how often it has been seen, and how many are usually listed.
local function Summarise(itemID, l, e)
  local rows = {}
  for i = 1, #l, 2 do rows[#rows + 1] = { l[i], l[i + 1] } end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  local qty = 0
  for _, r in ipairs(rows) do qty = qty + r[2] end
  local want, acc, m = math.max(1, qty * 0.25), 0, rows[#rows][1]
  for _, r in ipairs(rows) do
    acc = acc + r[2]
    if acc >= want then m = r[1] break end
  end
  e.prevAvg, e.prevSeen = e.avg, e.seen or 0
  SoldSince(e, rows)
  e.m, e.q = m, qty
  e.avg = e.avg and (e.avg * 0.7 + m * 0.3) or m
  e.qa = e.qa and (e.qa * 0.7 + qty * 0.3) or qty
  e.seen = (e.seen or 0) + 1
  return rows
end
Data.Summarise = Summarise

-------------------------------------------------------------------------------
-- Auction house: full scan
-------------------------------------------------------------------------------
local MODERN = C_AuctionHouse and C_AuctionHouse.ReplicateItems and true or false

local scanGot = nil -- listings the server sent for the running scan
local function FinishScan(n)
  scanning = false
  AskAHDB.lastScan = AskAHDB.lastScan or {}
  AskAHDB.lastScan[RealmKey()] = time()
  local items = 0
  local prices = Data.Prices()
  local all = listings or {}
  listings = nil
  local scanned = {}
  for itemID, l in pairs(all) do
    local e = prices[itemID]
    if e then
      local ok, rows = pcall(Summarise, itemID, l, e)
      if ok then scanned[itemID] = rows end
    end
  end
  for _, e in pairs(prices) do if e.pass == scanPass then items = items + 1 end end
  ns.Print(("scan done (%s): %d items priced."):format(ahIsNeutral and "neutral AH" or "faction AH", items))
  if ns.Deals and ns.Deals.FromScan then
    local ok, err = pcall(ns.Deals.FromScan, scanned, RealmKey(), ahIsNeutral)
    if not ok and AskAHDB.debug then ns.Print("deal check error: " .. tostring(err)) end
  end
  scanKey = nil
  ns.RefreshWindow()
end

-- Walk the listings a chunk per frame so the game doesn't freeze.
-- One bad listing never stops the scan: errors are counted and the first
-- one is reported when the scan finishes.
local scanErrors, scanFirstError = 0, nil
local function ProcessListings(total, getInfo)
  local i, CHUNK = 0, 2500
  scanErrors, scanFirstError = 0, nil
  scanGot = total
  if total == 0 then
    ns.Print("the auction house sent an empty list (the server may be busy or still on its scan cooldown). Try /askah scan in a few minutes.")
    scanning = false
    return
  end
  ns.Print(("got %d listings, reading them..."):format(total))
  local function step()
    local last = math.min(i + CHUNK, total) - 1
    for idx = i, last do
      local ok, err = pcall(function()
        local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = getInfo(idx)
        Record(itemID, name or (itemID and ItemName(itemID)), count, buyout, scanPass, owner)
      end)
      if not ok then
        scanErrors = scanErrors + 1
        scanFirstError = scanFirstError or tostring(err)
      end
    end
    i = last + 1
    if i < total then
      C_Timer.After(0, step)
    else
      local ok, err = pcall(FinishScan, total)
      if not ok then
        scanning = false
        ns.Print("scan read the listings but failed while saving: " .. tostring(err) .. " (please send this line to Claude)")
      end
      if scanErrors > 0 then
        ns.Print(("%d listings couldn't be read; first error: %s"):format(scanErrors, tostring(scanFirstError)))
      end
    end
  end
  step()
end

local scanFrame = CreateFrame("Frame")
scanFrame:SetScript("OnEvent", function(self, event)
  self:UnregisterAllEvents()
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    ProcessListings(n, function(idx) return C_AuctionHouse.GetReplicateItemInfo(idx) end)
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    local _, total = GetNumAuctionItems("list")
    total = total or 0
    -- classic list is 1-based
    ProcessListings(total, function(idx) return GetAuctionItemInfo("list", idx + 1) end)
  end
end)

local SCAN_COOLDOWN = 15 * 60  -- the server allows about one full scan per 15 min

local function LastScanStart()
  return AskAHDB.lastScanStart and AskAHDB.lastScanStart[RealmKey()] or 0
end
-- seconds until the next full scan is allowed here (0 = now)
function Data.NextScanIn() return math.max(0, SCAN_COOLDOWN - (time() - LastScanStart())) end
function Data.IsScanning() return scanning end
local lastSearch = 0 -- when you last searched the AH yourself
function Data.LastSearch() return lastSearch end

-- auto = true when called on opening the AH: stays silent if it's too soon.
function Data.Scan(auto)
  if not ahOpen then
    if not auto then ns.Print("open the auction house first, then /askah scan.") end
    return
  end
  if scanning then
    if not auto then ns.Print("a scan is already running.") end
    return
  end
  local wait = SCAN_COOLDOWN - (time() - LastScanStart())
  if wait > 0 then
    if not auto then ns.Print(("next full scan allowed in about %d min."):format(math.ceil(wait / 60))) end
    return
  end
  if not MODERN and QueryAuctionItems then
    local _, canAll = CanSendAuctionQuery()
    if not canAll then
      if not auto then ns.Print("the server isn't allowing a full scan yet. Try again in a few minutes.") end
      return
    end
  end
  if not MODERN and not QueryAuctionItems then
    if not auto then ns.Print("this client has no auction scan API I recognise.") end
    return
  end

  scanPass = time()
  listings = {}
  scanKey = RealmKey()
  AskAHDB.lastScanStart = AskAHDB.lastScanStart or {}
  AskAHDB.lastScanStart[RealmKey()] = scanPass
  scanning = true
  local which = ahIsNeutral and "neutral" or "faction"
  ns.Print((auto and "auto-scanning the %s auction house..." or "scanning the %s auction house..."):format(which))
  local wasAuto = auto
  scanGot = nil
  local ok, err
  if MODERN then
    scanFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    ok, err = pcall(C_AuctionHouse.ReplicateItems)
  else
    scanFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    ok, err = pcall(QueryAuctionItems, "", nil, nil, 0, false, nil, true)
  end
  if not ok then
    scanning = false
    scanFrame:UnregisterAllEvents()
    ns.Print("the scan request failed: " .. tostring(err))
    return
  end
  -- If the server never answers, don't stay stuck in "scanning". A full scan
  -- of a big AH can take a minute or two to arrive.
  local myPass = scanPass
  C_Timer.After(240, function()
    if scanning and scanPass == myPass and not scanGot then
      scanning = false
      listings = nil
      scanKey = nil
      scanFrame:UnregisterAllEvents()
      ns.Print("the auction house didn't send the scan within 4 minutes (the server may be busy or on its cooldown). Prices from your searches and the Blizzard feed still work. Try /askah scan later.")
    end
  end)
end

-------------------------------------------------------------------------------
-- Auction house: learn prices from your normal searches
-------------------------------------------------------------------------------
local passive = CreateFrame("Frame")
passive:RegisterEvent("AUCTION_HOUSE_SHOW")
passive:RegisterEvent("AUCTION_HOUSE_CLOSED")
if MODERN then
  passive:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  passive:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
else
  passive:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end
passive:SetScript("OnEvent", function(_, event, arg1)
  if event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    Data.DetectAH()
    -- Auto-scan every time you open the AH (if 15 min have passed).
    if AskAHDB and AskAHDB.autoScan ~= false then
      C_Timer.After(1, function() if ahOpen then Data.Scan(true) end end)
    end
    return
  end
  if event == "AUCTION_HOUSE_CLOSED" then ahOpen = false return end
  if scanning then return end
  local pass = "search" .. time()
  -- Listings you can see right now, per item ({unit, count}, your own left
  -- out), so the deals window can re-check its deals against them.
  local seen, complete = {}, false
  local function add(id, unit, count)
    if not id or not unit or unit <= 0 or not count or count <= 0 then return end
    seen[id] = seen[id] or {}
    local l = seen[id]
    l[#l + 1] = { unit, count }
  end
  local perAuction = true -- rows are single auctions (commodity results are merged per price)
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    perAuction = false
    local itemID = arg1
    local r = try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if r and r.unitPrice then
      local qty = try(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
      Record(itemID, ItemName(itemID), 1, r.unitPrice, pass)
      local e = Data.Prices()[itemID]
      if qty and e then e.q = qty end
    end
    local n = try(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
    for i = 1, math.min(n, 200) do
      local x = try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
      if x then add(itemID, x.unitPrice, (x.quantity or 0) - (x.numOwnerItems or 0)) end
    end
    seen[itemID] = seen[itemID] or {}
    complete = (try(C_AuctionHouse.HasFullCommoditySearchResults, itemID)) and true or false
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = arg1
    local r = itemKey and try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, 1)
    if r and r.buyoutAmount then
      Record(itemKey.itemID, ItemName(itemKey.itemID), 1, r.buyoutAmount, pass)
    end
    if itemKey and itemKey.itemID then
      local n = try(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
      for i = 1, math.min(n, 200) do
        local x = try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if x and x.buyoutAmount and not x.containsOwnerItem then
          local q = (x.quantity and x.quantity > 0) and x.quantity or 1
          add(itemKey.itemID, x.buyoutAmount, q)
        end
      end
      seen[itemKey.itemID] = seen[itemKey.itemID] or {}
      complete = (try(C_AuctionHouse.HasFullItemSearchResults, itemKey)) and true or false
    end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    local n, total = GetNumAuctionItems("list")
    n = n or 0
    local me = UnitName("player")
    for i = 1, n do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = GetAuctionItemInfo("list", i)
      Record(itemID, name, count, buyout, pass)
      if buyout and buyout > 0 and owner ~= me then
        local c = (count and count > 0) and count or 1
        add(itemID, buyout / c, c)
      end
    end
    -- a page of the browse tab; the leftover list after a full scan is huge,
    -- so leave that one alone
    if n > 200 then seen = {} end
    complete = (total or n) <= n
  end
  if next(seen) then lastSearch = time() end
  -- A complete look at an item's listings counts like a scan for "will it
  -- sell": compare with the last snapshot (5 min to 6 h old) and save a new one.
  if complete and perAuction then
    local prices = Data.Prices()
    for id, rows in pairs(seen) do
      local e = prices[id]
      if e and #rows > 0 then
        table.sort(rows, function(a, b) return a[1] < b[1] end)
        pcall(SoldSince, e, rows)
      end
    end
  end
  if ns.Deals and ns.Deals.OnLive and next(seen) ~= nil then
    local ok, err = pcall(ns.Deals.OnLive, seen, complete)
    if not ok and AskAHDB.debug then ns.Print("live deal check error: " .. tostring(err)) end
  end
  ns.RefreshWindow()
end)

-- Look up a price by item ID or (part of) a name.
function Data.FindPrices(query)
  local out = {}
  query = (query or ""):lower()
  for itemID, e in pairs(Data.Prices()) do
    local name = e.n or ItemName(itemID)
    if name and not e.n then e.n = name end
    if query == "" or (name and name:lower():find(query, 1, true)) or tostring(itemID) == query then
      out[#out + 1] = { id = itemID, n = name or ("item " .. itemID), p = e.p, q = e.q, t = e.t }
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

-------------------------------------------------------------------------------
-- Character stats
-------------------------------------------------------------------------------
local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }

function Data.SnapshotStats()
  -- Some combat values can be hidden ("secret") during combat on the modern
  -- client, so only read stats out of combat.
  if InCombatLockdown() then return end
  local hp = UnitHealthMax("player")
  if not hp or hp == 0 or (issecretvalue and issecretvalue(hp)) then return end
  local c = Data.Char()
  local s = {}
  s.level = UnitLevel("player")
  local _, class = UnitClass("player")
  s.class = class
  s.race = (UnitRace("player"))
  s.health = UnitHealthMax("player")
  s.power = UnitPowerMax("player")
  for i, name in ipairs(STAT_NAMES) do
    local _, eff = try(UnitStat, "player", i)
    s[name] = eff
  end
  local _, armor = try(UnitArmor, "player")
  s.Armor = armor
  local base, pos, neg = try(UnitAttackPower, "player")
  if base then s.AttackPower = base + (pos or 0) + (neg or 0) end
  s.Dodge = try(GetDodgeChance)
  s.Parry = try(GetParryChance)
  s.Block = try(GetBlockChance)
  s.BlockValue = try(GetShieldBlock)
  s.Crit = try(GetCritChance)
  local dBase, dMod = try(UnitDefense, "player")
  if dBase then s.Defense = dBase + (dMod or 0) end
  local speed = try(UnitAttackSpeed, "player")
  if speed then s.WeaponSpeed = speed end
  c.stats = s
  c.money = GetMoney()
  c.zone = GetRealZoneText and GetRealZoneText() or nil
  c.updated = time()
end

-------------------------------------------------------------------------------
-- Inventory
-------------------------------------------------------------------------------
local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.hyperlink end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
    return itemID, count, link
  end
end

local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
end

local function ReadBags(bagList)
  local items, used, total = {}, 0, 0
  for _, bag in ipairs(bagList) do
    local n = NumSlots(bag)
    total = total + n
    for slot = 1, n do
      local itemID, count, link = SlotInfo(bag, slot)
      if itemID then
        used = used + 1
        local e = items[itemID]
        if not e then
          e = { n = NameFromLink(link) or ItemName(itemID), c = 0, link = link }
          items[itemID] = e
        end
        e.c = e.c + (count or 1)
      end
    end
  end
  return items, used, total
end

local function CarriedBags()
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  local t = {}
  for b = 0, last do t[#t + 1] = b end
  return t
end

local function BankBags()
  local t = { BANK_CONTAINER or -1 }
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  local count = NUM_BANKBAGSLOTS or 7
  for b = first, first + count - 1 do t[#t + 1] = b end
  return t
end

local EQUIP_SLOTS = {
  "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist",
  "Hands", "Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back",
  "Main hand", "Off hand", "Ranged", "Tabard",
}

function Data.SnapshotInventory()
  local c = Data.Char()
  local items, used, total = ReadBags(CarriedBags())
  if total == 0 then return end -- bags not loaded yet (or logging out)
  c.bags = items
  c.bagSlots = { used = used, total = total }
  local eq = {}
  for i, slotName in ipairs(EQUIP_SLOTS) do
    local link = GetInventoryItemLink("player", i)
    if link then eq[#eq + 1] = { slot = slotName, n = NameFromLink(link), link = link } end
  end
  c.equipped = eq
  c.money = GetMoney()
  c.updated = time()
end

function Data.SnapshotBank(announce)
  local c = Data.Char()
  c.bank = (ReadBags(BankBags()))
  c.bankUpdated = time()
  if announce then ns.Print("bank contents saved.") end
end

-- Value of your bags at last-seen AH prices.
function Data.Worth()
  local c = Data.Char()
  local prices = Data.Prices("faction")
  local sum, rows = 0, {}
  for itemID, e in pairs(c.bags or {}) do
    local p = prices[itemID]
    if p then
      local v = p.p * e.c
      sum = sum + v
      rows[#rows + 1] = { n = e.n or ("item " .. itemID), c = e.c, v = v }
    end
  end
  table.sort(rows, function(a, b) return a.v > b.v end)
  return sum, rows
end

-------------------------------------------------------------------------------
-- Keep snapshots fresh (debounced)
-------------------------------------------------------------------------------
local pending = false
local function Refresh()
  if pending then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    if not AskAHDB then return end
    Data.SnapshotStats()
    Data.SnapshotInventory()
    ns.RefreshWindow()
    if ns.Deals and ns.Deals.QueueRefresh then ns.Deals.QueueRefresh() end
  end)
end
Data.Refresh = Refresh

local live = CreateFrame("Frame")
for _, ev in ipairs({
  "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
  "PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED",
  "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_LOGOUT",
}) do
  pcall(live.RegisterEvent, live, ev)
end
live:SetScript("OnEvent", function(_, event, arg1)
  if not AskAHDB then return end
  if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
  if event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
    Data.SnapshotBank(event == "BANKFRAME_OPENED")
  elseif event == "PLAYER_LOGOUT" then
    -- the game reports empty bags/zero stats while logging out: don't save that
    return
  else
    Refresh()
  end
end)
