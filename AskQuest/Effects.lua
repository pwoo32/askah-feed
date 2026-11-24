-- Effects.lua
-- Gives gear effects a value, not just plain stats: "Chance on hit:", "Equip:",
-- "Use:" and set bonuses. Each effect becomes stat points for your spec:
--   procs that deal damage   -> PDPS  (extra damage per second, counts like weapon DPS)
--   heals, drains, absorbs   -> HPS   (health per second, counts like Stamina)
--   stuns, slows, enemy-miss -> MIT   (% less damage taken, counts like Dodge)
--   stat or armor buffs      -> that stat, times how often it's up
--   attack speed / extra attacks -> WDPS (extra white swings: damage, threat
--                                     and rage, so they count like weapon DPS)
--   proc damage                  -> PDPS (threat, but no rage)
--   stuns and slows on the mob   -> MIT; fear, knockback and root count as 0
--     for a tank (a feared mob runs off and pulls more)
--   weapon skill ("Increased Swords +1") -> about 1 Expertise per point
-- How often a proc fires (WoW: Forever): weapon procs are 1 per minute scaled
-- by weapon speed (chance per hit = speed / 60, the Crusader rule), and they
-- also roll on instant attacks. "X% chance" effects use your swings per
-- minute, "when struck" effects use about 24 hits taken per minute (tanking
-- 1-2 mobs). On-use effects count for their duration / cooldown, times 0.8
-- because you won't press them on cooldown every time.
-- This file is the same in AskAH and AskQuest.
local _, ns = ...
local E = {}
ns.Effects = E

local HITS_TAKEN_PM = 24      -- melee hits you take per minute while tanking
local INSTANTS_PM = 8         -- Revenge, Sunder, Shield Slam, Thunder Clap... per minute
local USE_FACTOR = 0.8
local PCT_TO_RATING = { HIT = 10, CRIT = 14, DODGE = 12, PARRY = 15, BLOCK = 5 } -- Forever item ratings per 1%

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h, i, j, k, l, m, n = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h, i, j, k, l, m, n end
end

-------------------------------------------------------------------------------
-- Tooltip text of an item, cached
-------------------------------------------------------------------------------
local cache, scan = {}, nil
local function Lines(link)
  if not link then return {} end
  local c = cache[link]
  if c then return c end
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local data = try(C_TooltipInfo.GetHyperlink, link)
    if data and data.lines then
      for _, l in ipairs(data.lines) do
        if l.leftText then out[#out + 1] = l.leftText end
        if l.rightText then out[#out + 1] = l.rightText end
      end
    end
  end
  if #out == 0 and CreateFrame then
    if not scan then
      scan = CreateFrame("GameTooltip", "AskEffectsScanTT" .. tostring(math.random(1e6)), nil, "GameTooltipTemplate")
    end
    scan:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan:ClearLines()
    try(scan.SetHyperlink, scan, link)
    local name = scan:GetName()
    for i = 1, scan:NumLines() do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G[name .. "Text" .. side .. i]
        local t = fs and fs:GetText()
        if t and t ~= "" then out[#out + 1] = t end
      end
    end
    scan:Hide()
  end
  if #out > 1 then cache[link] = out end -- name only = not loaded yet, try again later
  return out
end
E.Lines = Lines

local function Clean(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-------------------------------------------------------------------------------
-- Parse one effect's text into stat points
-------------------------------------------------------------------------------
local STATWORDS = {
  { "attack power", "AP" }, { "strength", "STR" }, { "agility", "AGI" }, { "stamina", "STA" },
  { "armor", "ARMOR" }, { "defense", "DEFENSE" }, { "block value", "BLOCKVALUE" },
  { "intellect", "INT" }, { "spirit", "SPI" },
}

local function Num(s) return tonumber(s) end

local function Seconds(t)
  local n = tonumber(t:match("for (%d+%.?%d*) sec") or t:match("lasts (%d+%.?%d*) sec") or t:match("over (%d+%.?%d*) sec"))
  if n then return n end
  n = tonumber(t:match("for (%d+%.?%d*) min") or t:match("lasts (%d+%.?%d*) min"))
  return n and n * 60 or nil
end

local function Cooldown(t)
  local n, unit = t:match("%((%d+%.?%d*) (%a+) cooldown%)")
  n = tonumber(n)
  if not n then
    n, unit = t:match("(%d+%.?%d*) (%a+) cooldown")
    n = tonumber(n)
  end
  if not n then return nil end
  if unit:find("^min") then n = n * 60 elseif unit:find("^hour") then n = n * 3600 end
  return n
end

-- How much one firing does. Returns a table of stat -> amount per firing for
-- instant effects, plus { buff = {stat=amt}, dur = seconds } for timed ones.
local function Effect(t, ctx)
  local inst, buff = {}, {}
  local dur = Seconds(t)
  -- damage: "X to Y (school) damage", "for X (school) damage", "deals X"
  local a, b = t:match("(%d+) to (%d+) %a* ?damage")
  if not a then a, b = t:match("(%d+) to (%d+) damage") end
  local dmg = a and (Num(a) + Num(b)) / 2
  if not dmg then
    local x = t:match("drains? (%d+) health") or t:match("for (%d+) %a* ?damage") or t:match("for (%d+) damage") or t:match("deals? (%d+) %a* ?damage")
      or t:match("inflicts? (%d+) %a* ?damage") or t:match("(%d+) %a+ damage")
    dmg = tonumber(x)
  end
  if dmg and not t:find("absorb") and not t:find("damage taken") and not t:find("damage done") then
    inst.DMG = dmg
  end
  -- heals / drains
  local spellish = t:find("healing done") or t:find("spells") or t:find("healing spells")
  local heal = not spellish and t:match("heals? [%a ]-(%d+) to (%d+)")
  if spellish then heal = nil
  elseif heal then
    local h1, h2 = t:match("heals? [%a ]-(%d+) to (%d+)")
    heal = (Num(h1) + Num(h2)) / 2
  else
    heal = tonumber(t:match("heals? [%a ]-for (%d+)") or t:match("restores? (%d+) health") or t:match("heals? [%a ]-(%d+)"))
  end
  if t:find("drain") and inst.DMG then heal = heal or inst.DMG end
  if heal and not t:find("every 5 sec") then inst.HEAL = heal end
  local hp5 = t:match("restores? (%d+) health every 5 sec")
  if hp5 then inst.HP5 = Num(hp5) end
  local absorb = t:match("absorbs? (%d+)")
  if absorb then inst.ABSORB = Num(absorb) end
  -- attack speed, extra attacks
  local haste = t:match("attack speed by (%d+)%%")
  if haste and not t:find("target") and not t:find("enemy") and not t:find("its ") then buff.HASTE = Num(haste) end
  local extra = t:match("(%d+) extra attacks?") or (t:find("an extra attack") and "1") or (t:find("one extra attack") and "1")
  if extra then inst.EXTRA = Num(extra) end
  -- target debuffs that lower damage you take
  -- only effects that stop the mob hitting you while it stays on you
  local stun = (t:find("stun") or t:find("incapacitat")) and not t:find("stun resist")
  if stun then inst.CC = dur or 2 end
  local slow = t:match("attack speed[%a ]-reduced by (%d+)%%") or t:match("reduces? [%a' ]-attack speed by (%d+)%%")
    or t:match("slow[%a ]-attack[%a ]-by (%d+)%%")
  if slow then inst.SLOW = { Num(slow), dur or 10 } end
  -- mob's attack power lowered: "reduces the target's attack power by 100"
  local apdown = t:match("reduces? [%a' ]-attack power by (%d+)") or t:match("lowers? [%a' ]-attack power by (%d+)")
  if apdown and (t:find("target") or t:find("enem") or t:find("its ")) then inst.APDOWN = { Num(apdown), dur or 10 } end
  -- weapon skill: "Increased Swords +1", "+2 Axe skill". Forever keeps weapon
  -- skill but gear gives far less of it; each point lowers miss, dodge and
  -- parry a little, about what 1 Expertise does.
  local wsk = t:match("increased [%a%- ]-%+(%d+)") or t:match("%+(%d+) [%a%- ]-skill")
  if wsk and (t:find("sword") or t:find("axe") or t:find("mace") or t:find("dagger") or t:find("fist") or t:find("polearm") or t:find("staves")) then
    buff.EXP = (buff.EXP or 0) + Num(wsk)
  end
  local arpen = t:match("reduces? [%a' ]-armor by (%d+)") or t:match("lowers? [%a' ]-armor by (%d+)")
  if arpen then inst.ARPEN = { Num(arpen), dur or 20 } end
  -- stat buffs on you
  for _, sw in ipairs(STATWORDS) do
    local n = t:match("increases? your " .. sw[1] .. " by (%d+)") or t:match("increases? " .. sw[1] .. " by (%d+)")
      or t:match("increasing your " .. sw[1] .. " by (%d+)") or t:match("%+(%d+) " .. sw[1]) or t:match(sw[1] .. " increased by (%d+)") or t:match(sw[1] .. " %+(%d+)")
    if n and not (sw[2] == "ARMOR" and (t:find("reduc") or t:find("lower"))) then buff[sw[2]] = (buff[sw[2]] or 0) + Num(n) end
  end
  -- Forever rating wording: "Increases your hit rating by 10", "Improves
  -- expertise rating by 5", "defense rating by 7"
  for word, key in pairs({ hit = "HIT", ["critical strike"] = "CRIT", crit = "CRIT", dodge = "DODGE",
                           parry = "PARRY", block = "BLOCK", defense = "DEFENSE", expertise = "EXP",
                           haste = "HASTE_RATING" }) do
    local n = t:match(word .. " rating by (%d+)")
    if n then buff[key] = (buff[key] or 0) + Num(n) end
  end
  for word, key in pairs({ ["chance to block"] = "BLOCK", ["chance to dodge"] = "DODGE", ["chance to parry"] = "PARRY",
                           ["chance to hit"] = "HIT", ["a critical strike"] = "CRIT" }) do
    local n = t:match(word .. "[%a ]-by (%d+%.?%d*)%%")
    if n then buff[key] = (buff[key] or 0) + Num(n) * PCT_TO_RATING[key] end
  end
  -- Forever's unnamed expertise: "reduces the chance your attacks are dodged
  -- or parried by 1%" (10 Expertise rating = 1%)
  if (t:find("dodged") or t:find("parried")) and not t:find("enem") then
    local x = t:match("by (%d+%.?%d*)%%")
    if x then buff.EXP = (buff.EXP or 0) + Num(x) * 10
    else x = t:match("by (%d+)"); if x then buff.EXP = (buff.EXP or 0) + Num(x) end end
  end
  local bv = t:match("block value of your shield by (%d+)")
  if bv then buff.BLOCKVALUE = (buff.BLOCKVALUE or 0) + Num(bv) end
  local thr = t:match("threat[%a ]-by (%d+)%%")
  if thr and not t:find("reduc") then buff.THREAT = Num(thr) end
  return inst, buff, dur
end

-- Add the value of the effects (stat points, times how often they're up) into s.
local function Apply(s, inst, buff, uptime, perMin, ctx, isEquip)
  if inst.DMG then s.PDPS = (s.PDPS or 0) + inst.DMG * perMin / 60 end
  if inst.HEAL then s.HPS = (s.HPS or 0) + inst.HEAL * perMin / 60 end
  if inst.ABSORB then s.HPS = (s.HPS or 0) + inst.ABSORB * math.min(perMin, 1) / 60 end
  if inst.HP5 then s.HPS = (s.HPS or 0) + inst.HP5 / 5 end
  if inst.EXTRA then
    s.WDPS = (s.WDPS or 0) + inst.EXTRA * ctx.wdps * ctx.wspeed * perMin / 60
  end
  if inst.CC then s.MIT = (s.MIT or 0) + math.min(1, inst.CC * perMin / 60) * 100 * 0.5 end -- one of ~2 mobs
  if inst.SLOW then
    local up = math.min(1, inst.SLOW[2] * perMin / 60)
    s.MIT = (s.MIT or 0) + inst.SLOW[1] * up * 0.5
  end
  if inst.APDOWN then
    -- 14 mob AP = 1 mob DPS; a same-level mob hits for about (level + 1) DPS
    local up = math.min(1, inst.APDOWN[2] * perMin / 60)
    local lvl = (UnitLevel and UnitLevel("player")) or 30
    s.MIT = (s.MIT or 0) + math.min(50, inst.APDOWN[1] / 14 / (lvl + 1) * 100) * up * 0.5
  end
  if inst.ARPEN then
    local up = math.min(1, inst.ARPEN[2] * perMin / 60)
    -- ~1.5% more physical damage per 100 armor removed at mid levels
    s.PDPS = (s.PDPS or 0) + ctx.wdps * inst.ARPEN[1] / 100 * 0.015 * up
  end
  for bk, v in pairs(buff) do
    -- HASTE is attack speed %; HASTE_RATING is haste rating, scored as HASTE
    local k = (bk == "HASTE_RATING") and "HASTE" or bk
    if bk == "HASTE" then
      s.WDPS = (s.WDPS or 0) + ctx.wdps * v / 100 * uptime
    else
      -- plain Equip stats already read by the game are not added twice
      if isEquip and (s[k] or 0) > 0 then
        -- already in the item's stats. Items from Classic data store "1% crit"
        -- as 1, not Forever's 14 rating: keep the bigger reading.
        if v * uptime > s[k] then s[k] = v * uptime end
      else
        s[k] = (s[k] or 0) + v * uptime
        -- procs and on-use buffs are also kept under X_ so a Pawn scale
        -- (which can't value them) can have them added back
        if uptime < 1 then s["X_" .. k] = (s["X_" .. k] or 0) + v * uptime end
      end
    end
  end
end

-- One line of text (Equip / Chance on hit / Use / Set): what it adds to s.
function E.AddText(s, text, ctx, kind)
  local t = Clean(text):lower()
  kind = kind or (t:find("^use:") and "use") or (t:find("chance on") and "proc") or "equip"
  local inst, buff, dur = Effect(t, ctx)
  if not next(inst) and not next(buff) then return false end
  local perMin, uptime
  local pct = tonumber(t:match("(%d+%.?%d*)%% chance"))
  local struck = t:find("when struck") or t:find("when hit") or t:find("when you are hit")
  if kind == "use" then
    local cd = Cooldown(t) or 120
    perMin = 60 / cd * USE_FACTOR
    uptime = math.min(1, (dur or 0) / cd) * USE_FACTOR
  elseif kind == "proc" or pct or struck then
    if struck then perMin = (pct and pct / 100 or 1) * HITS_TAKEN_PM
    elseif pct then perMin = pct / 100 * (60 / ctx.wspeed + INSTANTS_PM)
    else perMin = (ctx.wspeed / 60) * (60 / ctx.wspeed + INSTANTS_PM) end -- 1 PPM, rolls on instants too
    uptime = dur and math.min(1, perMin * dur / 60) or 0
  else
    perMin, uptime = 0, 1 -- always on (Equip: +X ...)
  end
  Apply(s, inst, buff, uptime, perMin, ctx, kind == "equip" and not (pct or struck))
  return true
end

-- Your weapon context: main-hand DPS and speed (for haste / extra attack / PPM).
local function MainHand()
  local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
  local speed, dps = 2.6, 10
  if link then
    for _, l in ipairs(Lines(link)) do
      local sp = l:match("Speed (%d+%.%d+)")
      if sp then speed = tonumber(sp) end
      local d = l:match("%((%d+%.?%d*) damage per second%)")
      if d then dps = tonumber(d) end
    end
  end
  return speed, dps
end

-------------------------------------------------------------------------------
-- Enchants and added stats
-------------------------------------------------------------------------------
-- Enchants that only show their name on the item: what they do (Classic text).
local NAMED = {
  ["crusader"] = "Chance on hit: Heal self for 75 to 125 and Increases Strength by 100 for 15 sec.",
  ["fiery weapon"] = "Chance on hit: Deals 40 Fire damage.",
  ["lifestealing"] = "Chance on hit: Drains 30 health from the target.",
  ["icy chill"] = "Chance on hit: Reduces the target's attack speed by 15% for 5 sec.",
  ["unholy weapon"] = "Chance on hit: Deals 15 Shadow damage.",
}
local WORDS = { strength = "STR", agility = "AGI", stamina = "STA", intellect = "INT", spirit = "SPI",
  armor = "ARMOR", defense = "DEFENSE", ["attack power"] = "AP", ["block value"] = "BLOCKVALUE",
  block = "BLOCK", dodge = "DODGE", parry = "PARRY", hit = "HIT", ["critical strike"] = "CRIT", crit = "CRIT",
  expertise = "EXP", haste = "HASTE" }

-- "+7 Stamina", "+1% Dodge", "+3 Weapon Damage", "+4 All Stats", "+50 Health",
-- "+10 Fire Resistance". Adds to t, returns true if it read the line.
local function PlusLine(t, low, ctx, isWeapon)
  low = low:gsub("^enchanted: ", ""):gsub("^%a[%a ]- %((.-)%)$", "%1") -- "Reinforced (+24 Armor)" -> "+24 armor"
  local n, pct, word = low:match("^%+(%d+%.?%d*)(%%?) ([%a ]+)%.?$")
  n = tonumber(n)
  if not n then return false end
  word = word:gsub("%s+$", ""):gsub(" rating$", "")
  if word == "weapon damage" or word == "damage" then
    if isWeapon then t.DPS = (t.DPS or 0) + n / ctx.wspeed end
    return true
  elseif word == "all stats" or word == "to all stats" then
    for _, k in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do t[k] = (t[k] or 0) + n end
    return true
  elseif word == "health" or word == "hit points" then
    t.STA = (t.STA or 0) + n / 10
    return true
  elseif word:find("resistance") then
    t.RES = (t.RES or 0) + n * (word:find("all") and 5 or 1)
    return true
  end
  local key = WORDS[word]
  if not key then return false end
  if pct == "%" then n = n * (PCT_TO_RATING[key] or 1) end
  t[key] = (t[key] or 0) + n
  return true
end

local function BaseLink(link)
  return (link:gsub("(item:%-?%d+):%-?%d*", "%1:", 1))
end
local function EnchantID(link) return tonumber(link and link:match("item:%-?%d+:(%-?%d+)")) or 0 end

-- Tooltip lines that come from the enchant: lines the enchanted link has and
-- the bare item doesn't.
local enchCache = {}
function E.EnchantLines(link)
  if not link or EnchantID(link) == 0 then return {} end
  if enchCache[link] then return enchCache[link] end
  local with, base = Lines(link), Lines(BaseLink(link))
  if #with <= 1 or #base <= 1 then return {} end
  local count = {}
  for _, l in ipairs(base) do count[l] = (count[l] or 0) + 1 end
  local out = {}
  for _, l in ipairs(with) do
    if (count[l] or 0) > 0 then count[l] = count[l] - 1 else out[#out + 1] = Clean(l) end
  end
  enchCache[link] = out
  return out
end

-- Add every effect of an item (link) into stats table s: Equip/Use/Chance on
-- hit lines, the enchant on it, and any "+X Stat" line the stat data missed
-- (random "of the Bear" suffixes). Returns the texts it counted.
function E.Add(s, link, isWeapon)
  local lines = Lines(link)
  if #lines == 0 then return {} end
  local wspeed, wdps = MainHand()
  if isWeapon then
    -- the new weapon's own speed and DPS drive its procs (Blizzard data first,
    -- then what the tooltip prints)
    local B = AskAHBlizzAPI
    local g = B and B.Gear and B.Gear(tonumber(link:match("item:(%d+)")))
    if g and g.speed and g.speed > 0 then wspeed = g.speed end
    if g and g.dps and g.dps > 0 then wdps = g.dps end
    for _, l in ipairs(lines) do
      local sp = l:match("Speed (%d+%.%d+)"); if sp then wspeed = tonumber(sp) end
      local d = l:match("%((%d+%.?%d*) damage per second%)"); if d then wdps = tonumber(d) end
    end
  end
  local ctx = { wspeed = wspeed, wdps = wdps }
  local used = {}
  local ench = {}
  for _, l in ipairs(E.EnchantLines(link)) do ench[l] = true end
  local tip, enchStats = {}, {}
  for _, l in ipairs(lines) do
    local c = Clean(l)
    local low = c:lower()
    if ench[c] then
      -- the enchant: added on top of the item's own stats
      local e = {}
      local name = low:gsub("^enchanted: ", "")
      if NAMED[name] then E.AddText(s, NAMED[name], ctx, "proc"); used[#used + 1] = c
      elseif PlusLine(e, low, ctx, isWeapon) then
        for k, v in pairs(e) do enchStats[k] = (enchStats[k] or 0) + v end
        used[#used + 1] = c
      elseif E.AddText(s, c, ctx) then used[#used + 1] = c end
    elseif not low:find("^%(%d%)") and not low:find("^set:") then
      -- tooltip set lines are counted from the set data instead
      if low:find("^chance on hit:") or low:find("^use:") or low:find("^equip:") then
        if E.AddText(s, c, ctx) then used[#used + 1] = c end
      elseif low:find("^%+%d") then
        PlusLine(tip, low, ctx, false)
      else
        local blk = low:match("^(%d+) block$")       -- a shield's own block value
        if blk then tip.BLOCKVALUE = tonumber(blk) end
      end
    end
  end
  -- Stats printed on the item that the stat data didn't have (random suffixes).
  for k, v in pairs(tip) do
    if k ~= "DPS" and v > (s[k] or 0) then s[k] = v end
  end
  for k, v in pairs(enchStats) do s[k] = (s[k] or 0) + v end
  return used
end

-- The enchant on an item, as short text ("Crusader", "+7 Stamina"), or nil.
function E.EnchantText(link)
  local l = E.EnchantLines(link)
  if #l == 0 then return nil end
  return (table.concat(l, ", "):gsub("^Enchanted: ", ""))
end

-------------------------------------------------------------------------------
-- Set bonuses: what swapping an item in changes about your active bonuses.
-------------------------------------------------------------------------------
local function SetData(id)
  local B = AskAHBlizzAPI or (ns.Blizz)
  if not (B and B.SetOf) then return nil end
  return B.SetOf(id)
end

local function IDof(link) return link and tonumber(link:match("item:(%d+)")) end

-- score(stats) -> number. Returns extra score points for wearing newLink
-- instead of oldLink, from set bonuses, and a short text.
function E.SetDelta(newLink, oldLink, score)
  local newID, oldID = IDof(newLink), IDof(oldLink)
  local sid, set = SetData(newID)
  local osid, oset = SetData(oldID)
  if not sid and not osid then return 0 end
  local wspeed, wdps = MainHand()
  local ctx = { wspeed = wspeed, wdps = wdps }
  local function Have(set)
    local n = 0
    for _, iid in ipairs(set.i or {}) do
      for slot = 1, 19 do
        if IDof(GetInventoryItemLink("player", slot)) == iid then n = n + 1; break end
      end
    end
    return n
  end
  local function Value(set, count)
    local s = {}
    for _, e in ipairs(set.e or {}) do
      local n, txt = e:match("^(%d+):(.*)$")
      if n and tonumber(n) <= count then E.AddText(s, (txt:gsub("^Set: ", "")), ctx, "set") end
    end
    return score(s)
  end
  local function Next(set, count) -- the next bonus you'd get, counted at 15% per piece toward it
    local best
    for _, e in ipairs(set.e or {}) do
      local n = tonumber(e:match("^(%d+):"))
      if n and n > count and (not best or n < best) then best = n end
    end
    if not best then return 0 end
    return (Value(set, best) - Value(set, count)) * 0.15 * count
  end
  local delta, text = 0, nil
  if sid and sid ~= osid then
    local have = Have(set)
    local gain = Value(set, have + 1) - Value(set, have) + Next(set, have + 1) - Next(set, have)
    delta = delta + gain
    if gain > 0.05 then text = ("set: %d of %d %s"):format(have + 1, #set.i, set.n) end
  end
  if osid and osid ~= sid then
    local have = Have(oset)
    delta = delta - (Value(oset, have) - Value(oset, have - 1) + Next(oset, have) - Next(oset, have - 1))
  end
  return delta, text
end

-------------------------------------------------------------------------------
-- Pawn / Ask Mr. Robot. If Pawn is installed and has a scale from Ask Mr.
-- Robot (made by the AMR addon after "Send to Addon" on askmrrobot.com),
-- gear scores use that scale, plus what Pawn can't value: procs, Use effects,
-- set bonuses. /askah pawn picks the scale or turns this off.
-------------------------------------------------------------------------------
local function ScaleList()
  if type(PawnGetAllScalesEx) ~= "function" then return nil end
  local ok, list = pcall(PawnGetAllScalesEx)
  return ok and type(list) == "table" and list or nil
end
E.PawnScales = ScaleList

function E.PawnScale()
  local want = AskAHDB and AskAHDB.pawnScale
  if want == "off" then return nil end
  local list = ScaleList()
  if not list then return nil end
  local best, bestRank
  for _, sc in ipairs(list) do
    local name = sc.Name or sc.ScaleName
    local label = ((sc.LocalizedName or name or "") .. " " .. (sc.Header or "") .. " " .. (name or "")):lower()
    local rank
    if want and want ~= "auto" then
      if name == want or (sc.LocalizedName or ""):lower() == want:lower() then rank = 100 end
    elseif label:find("amr") or label:find("mr%. ?robot") or label:find("mrrobot") then
      rank = 10
      if label:find("prot") or label:find("tank") then rank = rank + 5 end
      if sc.IsVisible then rank = rank + 2 end
    end
    if rank and (not bestRank or rank > bestRank) then best, bestRank = sc, rank end
  end
  if not best then return nil end
  return best.Name or best.ScaleName, best.LocalizedName or best.Name
end

-- Pawn's value of an item on a scale (enchant included), or nil.
function E.PawnValue(link, scale)
  if not (link and scale and type(PawnGetItemData) == "function" and type(PawnGetSingleValueFromItem) == "function") then return nil end
  local ok, item = pcall(PawnGetItemData, link)
  if not ok or not item then return nil end
  local ok2, v = pcall(PawnGetSingleValueFromItem, item, scale)
  if ok2 and type(v) == "number" then return v end
  return nil
end

-- How many Pawn points one Stamina (or Strength) is on that scale, to turn
-- AskAH's extras into the same units.
function E.PawnPer(scale, key)
  local sc = PawnCommon and PawnCommon.Scales and PawnCommon.Scales[scale]
  local v = sc and sc.Values
  if not v then return nil end
  local names = { STA = "Stamina", STR = "Strength", AGI = "Agility" }
  local n = v[names[key] or key]
  return (type(n) == "number" and n > 0) and n or nil
end

-------------------------------------------------------------------------------
-- Stat names from Blizzard's API data that the scorer doesn't know, and
-- Classic-data items whose Equip "%" stats were stored as 1 instead of rating.
-------------------------------------------------------------------------------
local RAW = { EXTRA_ARMOR = "ARMOR", EXPERTISE_RATING = "EXP", HASTE_RATING = "HASTE",
  FIRE_RESISTANCE = "RES", FROST_RESISTANCE = "RES", NATURE_RESISTANCE = "RES",
  SHADOW_RESISTANCE = "RES", ARCANE_RESISTANCE = "RES", HOLY_RESISTANCE = "RES" }
local CLASSIC_PCT = { HIT = 10, CRIT = 14, DODGE = 12, PARRY = 15, BLOCK = 5 }
function E.Normalize(s, link)
  for raw, key in pairs(RAW) do
    if s[raw] then s[key] = (s[key] or 0) + s[raw]; s[raw] = nil end
  end
  if s.HEALTH_REGEN then s.HPS = (s.HPS or 0) + s.HEALTH_REGEN / 5; s.HEALTH_REGEN = nil end
  if s.HP5 then s.HPS = (s.HPS or 0) + s.HP5 / 5; s.HP5 = nil end
  local id = link and tonumber(link:match("item:(%d+)"))
  local B = AskAHBlizzAPI
  local it = id and B and B.Item and B.Item(id)
  if it and it.classic then
    for k, mult in pairs(CLASSIC_PCT) do
      if s[k] and s[k] > 0 and s[k] <= 5 then s[k] = s[k] * mult end
    end
  end
  return s
end

-- Is this item from Blizzard's Classic data (Forever's own list lacks it)?
function E.IsClassicData(link)
  local id = link and tonumber(link:match("item:(%d+)"))
  local B = AskAHBlizzAPI
  local it = id and B and B.Item and B.Item(id)
  return it and it.classic or false
end
