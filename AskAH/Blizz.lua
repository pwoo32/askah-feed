-- Blizz.lua
-- Game data from Blizzard's API (items, gear stats, item sets, recipes),
-- written to BlizzData.lua by Feed\AskStatic.ps1. Fills the gaps in what the
-- game client knows: items you've never seen (so they're not cached), vendor
-- prices, gear stats for upgrade checks, set pieces, and every recipe with
-- its reagents. AskQuest uses it too, through the global AskAHBlizzAPI.
local _, ns = ...
local B = {}
ns.Blizz = B
AskAHBlizzAPI = B

local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo  -- the game's own lookup
local GREY, GREEN, BLUE = "|cff999999", "|cff33ff33", "|cff33ccff"

function B.Available() return type(AskAHBlizz) == "table" and type(AskAHBlizz.items) == "table" end

local function Split(s, sep)
  local out, i = {}, 1
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[i] = part; i = i + 1 end
  return out
end

-- API inventory types -> the game's equipLoc names
local INV = { TWOHWEAPON = "INVTYPE_2HWEAPON", NON_EQUIP = "" }
local function EquipLoc(t)
  if not t or t == "" then return "" end
  if INV[t] then return INV[t] end
  return "INVTYPE_" .. t
end

local itemCache = {}
-- { id, name, quality, ilvl, req, classID, subID, equipLoc, sell, buy, stack, classic }
function B.Item(id)
  id = tonumber(id)
  if not id or not B.Available() then return nil end
  local c = itemCache[id]
  if c ~= nil then return c or nil end
  local s = AskAHBlizz.items[id]
  if not s then itemCache[id] = false; return nil end
  local p = Split(s, "|")
  c = { id = id, name = p[1], quality = tonumber(p[2]) or 1, ilvl = tonumber(p[3]) or 0, req = tonumber(p[4]) or 0,
        classID = tonumber(p[5]), subID = tonumber(p[6]), equipLoc = EquipLoc(p[7]), sell = tonumber(p[8]) or 0,
        buy = tonumber(p[9]) or 0, stack = p[10] == "1", classic = p[11] == "c" }
  itemCache[id] = c
  return c
end

local gearCache = {}
-- { armor, dps, speed, min, max, stats = { STR = 5, ... }, set, classes = { [classID] = true }, bind }
function B.Gear(id)
  id = tonumber(id)
  if not id or not B.Available() then return nil end
  local c = gearCache[id]
  if c ~= nil then return c or nil end
  local s = AskAHBlizz.gear[id]
  if not s or s == "" then gearCache[id] = false; return nil end
  local p = Split(s, "|")
  c = { armor = tonumber(p[1]) or 0, dps = tonumber(p[2]) or 0, speed = (tonumber(p[3]) or 0) / 1000,
        min = tonumber(p[4]), max = tonumber(p[5]), stats = {}, set = tonumber(p[7]), bind = tonumber(p[9]) }
  for k, v in (p[6] or ""):gmatch("([%w_]+):(%-?%d+)") do c.stats[k] = (c.stats[k] or 0) + tonumber(v) end
  if p[8] and p[8] ~= "" then
    c.classes = {}
    for x in p[8]:gmatch("%d+") do c.classes[tonumber(x)] = true end
  end
  gearCache[id] = c
  return c
end

-- Stats in AskAH's short names (same as the tooltip's GetItemStats reading).
function B.Stats(id)
  local g = B.Gear(id)
  if not g then return nil end
  local s = {}
  for k, v in pairs(g.stats) do s[k] = v end
  if g.armor > 0 then s.ARMOR = (s.ARMOR or 0) + g.armor end
  if g.dps > 0 then s.DPS = g.dps end
  return s
end

-- Like C_Item.GetItemInfo, from Blizzard's data, for items the game hasn't loaded.
-- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sell, classID, subID, bind
function B.ItemInfo(id)
  local it = B.Item(id)
  if not it then return nil end
  local g = B.Gear(id)
  local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
  local hex = q and q.hex or "|cffffffff"
  local link = ("%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(hex, it.id, it.name)
  return it.name, link, it.quality, it.ilvl, it.req, nil, nil, it.stack and 20 or 1, it.equipLoc, nil, it.sell,
         it.classID, it.subID, g and g.bind or nil
end

-- Item ID from a number, "item:123" or a full link, and whether the link has a
-- random suffix ("of the Bear"): those stats only the game knows.
function B.LinkID(item)
  if type(item) == "number" then return item, false end
  if type(item) ~= "string" then return nil, false end
  local id = tonumber(item:match("item:(%d+)"))
  if not id then return nil, false end
  local suffix = tonumber(item:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)") or "0") or 0
  return id, suffix ~= 0
end

-- API data first, the game second. Same return values as C_Item.GetItemInfo.
-- The game still supplies the link, icon and type names; Blizzard's API
-- supplies name, quality, item level, required level, vendor price, class,
-- subclass and binding. Items with a random suffix stay with the game's data.
function B.GetItemInfo(item)
  local g = { pcall(GII, item) }
  local ok = table.remove(g, 1)
  if not ok then g = {} end
  local id, suffix = B.LinkID(item)
  local it = id and not suffix and B.Item(id)
  if not it then return unpack(g, 1, 18) end
  if g[1] == nil then return B.ItemInfo(id) end
  local gear = B.Gear(id)
  g[1], g[3], g[4], g[5], g[11], g[12], g[13] = it.name, it.quality, it.ilvl, it.req, it.sell, it.classID, it.subID
  if (g[9] == nil or g[9] == "") and it.equipLoc ~= "" then g[9] = it.equipLoc end
  if gear and gear.bind then g[14] = gear.bind end
  return unpack(g, 1, 18)
end

-- Stats: API first (except random-suffix items), else nil so the caller asks the game.
function B.StatsFirst(link)
  local id, suffix = B.LinkID(link)
  if not id or suffix then return nil end
  return B.Stats(id)
end

-------------------------------------------------------------------------------
-- Item sets
-------------------------------------------------------------------------------
local setOf
function B.SetOf(id)
  id = tonumber(id)
  if not id or not B.Available() then return nil end
  if not setOf then
    setOf = {}
    for sid, set in pairs(AskAHBlizz.sets or {}) do
      for _, iid in ipairs(set.i or {}) do setOf[iid] = sid end
    end
  end
  local sid = setOf[id]
  return sid, sid and AskAHBlizz.sets[sid]
end

local function Equipped(id)
  for slot = 1, 19 do
    local l = GetInventoryItemLink("player", slot)
    if l and tonumber(l:match("item:(%d+)")) == id then return true end
  end
  return false
end

function B.SetLines(id)
  local sid, set = B.SetOf(id)
  if not set then return nil end
  local have = 0
  for _, iid in ipairs(set.i) do if Equipped(iid) then have = have + 1 end end
  local lines = { ("Set: %s" .. GREY .. " (you wear %d of %d)|r"):format(set.n, have, #set.i) }
  for _, e in ipairs(set.e or {}) do
    local n, txt = e:match("^(%d+):(.*)$")
    if n then
      local col = tonumber(n) <= have and GREEN or GREY
      lines[#lines + 1] = ("   %s(%s) %s|r"):format(col, n, (txt:gsub("^Set: ", "")))
    end
  end
  return lines
end

-------------------------------------------------------------------------------
-- Recipes: what uses this item, and what a recipe costs to make.
-------------------------------------------------------------------------------
local recipeCache, usedIn, madeBy = {}, nil, nil
-- { id, name, prof, cat, out, qty, reagents = { [itemID] = n } }
function B.Recipe(rid)
  rid = tonumber(rid)
  local c = recipeCache[rid]
  if c then return c end
  local s = B.Available() and AskAHBlizz.recipes[rid]
  if not s then return nil end
  local p = Split(s, "|")
  c = { id = rid, name = p[1], prof = p[2], cat = p[3], out = tonumber(p[4]), qty = tonumber(p[5]) or 1, reagents = {} }
  for iid, n in (p[6] or ""):gmatch("(%d+):(%d+)") do c.reagents[tonumber(iid)] = tonumber(n) end
  recipeCache[rid] = c
  return c
end

local function Index()
  if usedIn then return end
  usedIn, madeBy = {}, {}
  if not B.Available() then return end
  for rid in pairs(AskAHBlizz.recipes) do
    local r = B.Recipe(rid)
    for iid in pairs(r.reagents) do
      usedIn[iid] = usedIn[iid] or {}
      table.insert(usedIn[iid], rid)
    end
    if r.out then madeBy[r.out] = madeBy[r.out] or {}; table.insert(madeBy[r.out], rid) end
  end
end

function B.UsedIn(id) Index(); return usedIn[tonumber(id)] end
function B.MadeBy(id) Index(); return madeBy[tonumber(id)] end

function B.RecipesFor(prof)
  local out = {}
  if not B.Available() then return out end
  for rid in pairs(AskAHBlizz.recipes) do
    local r = B.Recipe(rid)
    if r.prof == prof then out[#out + 1] = r end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Cheapest way to get one reagent: AH (your faction's house) or vendor.
local function UnitCost(iid)
  local fe = ns.Data.Prices("faction")[iid]
  local ah = fe and fe.p
  local it = B.Item(iid)
  local vendor = it and it.buy and it.buy > 0 and it.buy or nil
  -- vendor price only counts for things vendors really sell (trade goods with a buy price under the AH price)
  if ah and vendor then return math.min(ah, vendor), (vendor < ah) and "vendor" or "AH" end
  if ah then return ah, "AH" end
  return nil
end
B.UnitCost = UnitCost

-- Cost to craft one, from AH prices of the reagents. Returns cost, missing (count of reagents with no price).
function B.CraftCost(rid)
  local r = B.Recipe(rid)
  if not r then return nil end
  local cost, missing = 0, 0
  for iid, n in pairs(r.reagents) do
    local u = UnitCost(iid)
    if u then cost = cost + u * n else missing = missing + 1 end
  end
  return cost / math.max(r.qty, 1), missing
end

-------------------------------------------------------------------------------
-- Tooltip lines (called from Tooltip.lua)
-------------------------------------------------------------------------------
-- Tooltip lines. Without detail: one short line per topic. With detail
-- (Shift): set bonuses and the per-profession recipe counts too.
-- Returns lines, and whether detail was left out.
function B.TooltipLines(itemID, detail)
  if not B.Available() then return nil end
  local lines, more = {}, false

  local made = B.MadeBy(itemID)
  if made and #made > 0 then
    local r = B.Recipe(made[1])
    local cost, missing = B.CraftCost(made[1])
    if cost and cost > 0 then
      local txt = ns.Data.Money(math.floor(cost)) .. (missing > 0 and (GREY .. (" +%d unpriced|r"):format(missing)) or "")
      lines[#lines + 1] = ("Craft cost (%s): %s"):format(r.prof, txt)
    else
      lines[#lines + 1] = GREY .. ("Crafted by %s (no reagent prices yet)|r"):format(r.prof)
    end
  end

  local used = B.UsedIn(itemID)
  if used and #used > 0 then
    local per = {}
    for _, rid in ipairs(used) do local r = B.Recipe(rid); per[r.prof] = (per[r.prof] or 0) + 1 end
    local parts = {}
    for prof, n in pairs(per) do parts[#parts + 1] = detail and ("%s %d"):format(prof, n) or prof end
    table.sort(parts)
    lines[#lines + 1] = GREY .. ("Reagent in %d recipe%s: "):format(#used, #used == 1 and "" or "s") .. table.concat(parts, ", ") .. "|r"
  end

  local set = B.SetLines(itemID)
  if set then
    lines[#lines + 1] = set[1]
    if detail then for i = 2, #set do lines[#lines + 1] = set[i] end
    elseif #set > 1 then more = true end
  end
  return #lines > 0 and lines or nil, more
end

-------------------------------------------------------------------------------
-- /askah craft <profession>: most profitable recipes from AH prices
-------------------------------------------------------------------------------
function B.CraftReport(prof, n)
  n = n or 15
  if not B.Available() then ns.Print("no Blizzard data yet (Feed\\AskStatic.ps1 hasn't run).") return end
  prof = prof and prof:lower() or ""
  local name
  for rid in pairs(AskAHBlizz.recipes) do
    local r = B.Recipe(rid)
    if r.prof:lower():find(prof, 1, true) then name = r.prof break end
  end
  if not name then ns.Print("which profession? e.g. /askah craft tailoring") return end
  local rows = {}
  for _, r in ipairs(B.RecipesFor(name)) do
    local cost, missing = B.CraftCost(r.id)
    local fe = r.out and ns.Data.Prices("faction")[r.out]
    if cost and missing == 0 and fe and fe.p and fe.p > 0 then
      rows[#rows + 1] = { r = r, cost = cost, sell = fe.p, profit = math.floor(fe.p * 0.95 - cost) }
    end
  end
  table.sort(rows, function(a, b) return a.profit > b.profit end)
  ns.Print(("%s: most profitable to craft and sell (AH price after the 5%% cut, minus reagents)"):format(name))
  if #rows == 0 then print("   No recipe has prices for its result and all reagents yet.") return end
  for i = 1, math.min(n, #rows) do
    local x = rows[i]
    print(("  %d. %s: %s profit (sells %s, reagents %s)"):format(i, x.r.name,
      (x.profit >= 0 and "" or "|cffff4040") .. ns.Data.Money(math.abs(x.profit)) .. (x.profit >= 0 and "" or " loss|r"),
      ns.Data.Money(x.sell), ns.Data.Money(math.floor(x.cost))))
  end
end

function B.Status()
  if not B.Available() then
    ns.Print("Blizzard game data not loaded yet. It's written by Feed\\AskStatic.ps1 (the feed runs it).")
    return
  end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
  ns.Print(("Blizzard data, build %s, %s: %d items, %d with gear stats, %d recipes, %d item sets."):format(
    AskAHBlizz.build or "?", date("%b %d %H:%M", AskAHBlizz.t or 0), count(AskAHBlizz.items), count(AskAHBlizz.gear),
    count(AskAHBlizz.recipes), count(AskAHBlizz.sets)))
end

-------------------------------------------------------------------------------
-- /askah upgrades: gear for sale on your auction houses (hourly feed) that's
-- an upgrade for your spec, cheapest listing first within each slot.
-------------------------------------------------------------------------------
function B.UpgradesReport(n)
  n = n or 15
  local T = ns.Tooltip
  if not (B.Available() and T and T.UpgradeFor) then
    ns.Print("no Blizzard item data yet (Feed\\AskStatic.ps1 hasn't run).")
    return
  end
  if not (type(AskAHFeed) == "table" and type(AskAHFeed.houses) == "table") then
    ns.Print("no auction feed loaded yet (Feed\\Run-Feed.cmd).")
    return
  end
  local mine = UnitFactionGroup("player") == "Horde" and "horde" or "alliance"
  local best = {}
  for _, h in pairs(AskAHFeed.houses) do
    if h.kind == mine or h.kind == "blackwater" then
      for id, s in pairs(h.items or {}) do
        local it = B.Item(id)
        if it and it.equipLoc ~= "" then
          local price = tonumber(s:match("^(%d+)"))
          local ok, pct = pcall(T.UpgradeFor, id)
          if ok and pct and pct > 0 and price then
            local cur = best[id]
            if not cur or price < cur.price then
              best[id] = { id = id, it = it, pct = pct, price = price, where = h.kind == "blackwater" and "neutral" or "faction" }
            end
          end
        end
      end
    end
  end
  local rows = {}
  for _, r in pairs(best) do rows[#rows + 1] = r end
  table.sort(rows, function(a, b) if a.pct ~= b.pct then return a.pct > b.pct end return a.price < b.price end)
  ns.Print(("upgrades for sale (%s, level %d), biggest first:"):format(
    (T.SPEC_NAMES and T.SPEC_NAMES[T.Spec()]) or "your spec", UnitLevel("player") or 0))
  if #rows == 0 then print("   None found in the latest feed.") return end
  for i = 1, math.min(n, #rows) do
    local r = rows[i]
    local link = select(2, B.ItemInfo(r.id))
    print(("  %d. %s +%d%% for %s (%s AH)"):format(i, link or r.it.name, r.pct + 0.5, ns.Data.Money(r.price), r.where))
  end
  if #rows > n then print(GREY .. ("   %d more: /askah upgrades %d|r"):format(#rows - n, math.min(#rows, 50))) end
end
