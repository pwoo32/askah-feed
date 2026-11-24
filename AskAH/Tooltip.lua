-- Tooltip.lua
-- The main feature. When you hover an item, AskAH adds:
--   1. Auction house price (last seen) and vendor price
--   2. Advice: auction it, vendor it, or keep it
--   3. For gear: can you wear it, and is it an upgrade over what you have on,
--      scored with stat weights for your class/spec (Prot Warrior by default
--      when you have a shield on).
local _, ns = ...
local T = {}
ns.Tooltip = T

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h, i, j, k, l, m, n = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h, i, j, k, l, m, n end
end

local function Money(c) return ns.Data.Money(c) end

-- WoW: Forever runs the modern client: C_Item.GetItemInfo is the reliable
-- one; the old global GetItemInfo may not exist.
local GII = function(x) local B = AskAHBlizzAPI; if B and B.GetItemInfo then return B.GetItemInfo(x) end return ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(x) end -- Blizzard API data first, then the game
local GREEN, RED, YELLOW, GREY, BLUE = "|cff33ff33", "|cffff4040", "|cffffd200", "|cff999999", "|cff33ccff"
local DETAIL = "\001" -- marks a tooltip line that only shows with Shift held

-------------------------------------------------------------------------------
-- Stat weights (value per point). Prot is set from WoW Forever guides
-- (see the PROT notes below); it switches to PROT60 at level 58.
-------------------------------------------------------------------------------
local W = {
  -- Prot weights, Stamina = 1 (WoW Forever, Nov 2026 sources):
  --   wowhandbook.com Forever prot (leveling): Sta 1, Str 0.54, Agi 0.57,
  --     Hit 9.83 per 1%, Crit 7.06 per 1%.
  --   wowforeverbislist.com prot EP (60): Defense 15 to 440 then 0.46, Expertise
  --     20.43 per 1% to 6.5%, Block value 0.66, Crit 5.24 per 1%, Dodge 3.03 per 1%.
  --   MythicSim Forever prot threat sim (60): Str is the top threat stat after
  --     Expertise; Crit 0.85 of Str per rating.
  -- Forever item ratings: 10 hit/expertise = 1%, 14 crit = 1%, 12 dodge, 15 parry.
  -- Armor is not a fixed number: Armor() below works it out from your level,
  -- health and armor (how much damage 1 armor saves vs what 1 Stamina adds).
  -- Str is a bit above the sources' 0.54 because Revenge, Thunder Clap and
  -- Shield Slam scale with attack power in Forever. 1 weapon DPS = 14 AP on
  -- white hits only (abilities don't use weapon damage), so about 2.3.
  -- Defense while leveling: each point is +0.04% dodge, parry, block and
  -- enemy miss, and -0.04% enemy crit, and every avoided hit gives rage with
  -- Shield Specialization / Master of Defense. wowhandbook ranks it first for
  -- Forever prot. 1.0 per point (checked: Berserker Shackles, 7 Str + 6 Def,
  -- beat War Rider Bracers, 8 Sta + 3 Agi, as players report).
  PROT = { STA = 1.0, STR = 0.6, AGI = 0.57, ARMOR = 0.035, BLOCKVALUE = 0.4, BLOCK = 0.35,
           DODGE = 0.45, PARRY = 0.38, DEFENSE = 1.0, AP = 0.3, HIT = 0.98, CRIT = 0.5,
           EXP = 1.0, SPI = 0.03, DPS = 2.3, PDPS = 1.95, THREAT = 2.5, HASTE = 0.4 },
  -- 58+ (dungeons, then raids), from wowforeverbislist EP. Defense and Expertise
  -- drop off once you reach their caps (see Weights below).
  PROT60 = { STA = 1.0, DEFENSE = 15, HIT = 0.35, EXP = 2.04, ARMOR = 0.03, STR = 0.54,
             BLOCKVALUE = 0.66, AGI = 0.57, DODGE = 0.25, PARRY = 0.2, BLOCK = 0.2, AP = 0.27,
             CRIT = 0.37, SPI = 0.02, DPS = 2.0, PDPS = 1.7, THREAT = 4.0, HASTE = 0.38 },
  ARMS = { STR = 1.0, AGI = 0.8, STA = 0.3, AP = 0.5, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01,
           SPI = 0.1, DPS = 8.0 },
  FURY = { STR = 1.0, AGI = 0.8, STA = 0.3, AP = 0.5, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01,
           SPI = 0.1, DPS = 7.0 },
  ROGUE = { AGI = 1.0, STR = 0.5, STA = 0.3, AP = 0.5, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01, DPS = 7.0 },
  HUNTER = { AGI = 1.0, INT = 0.3, STA = 0.3, AP = 0.4, RAP = 0.4, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01, DPS = 1.0, RDPS = 7.0 },
  CASTER = { INT = 1.0, SPI = 0.6, STA = 0.4, SP = 0.9, HEAL = 0.4, CRIT = 0.5, ARMOR = 0.005, DPS = 0.2 },
  HEALER = { INT = 1.0, SPI = 0.8, STA = 0.4, HEAL = 0.9, SP = 0.3, MP5 = 1.5, ARMOR = 0.005, DPS = 0.2 },
  HYBRID = { STR = 1.0, AGI = 0.6, INT = 0.6, STA = 0.6, AP = 0.5, CRIT = 0.8, SP = 0.4, ARMOR = 0.03, DPS = 6.0 },
}

-- Weights for your spec right now. Prot: armor from your own character,
-- Defense/Expertise caps at 60, and the /askah focus setting
-- (threat: hit harder and hold aggro; survival: live through big pulls).
local FOCUS = {
  threat = { STR = 1.35, AP = 1.35, CRIT = 1.35, HIT = 1.35, EXP = 1.35, DPS = 1.35, PDPS = 1.35, WDPS = 1.35, THREAT = 1.35, AGI = 1.15,
             STA = 0.8, ARMOR = 0.8, DODGE = 0.8, PARRY = 0.8, BLOCK = 0.8, DEFENSE = 0.8, HPS = 0.8, MIT = 0.8 },
  survival = { STA = 1.3, ARMOR = 1.3, DODGE = 1.3, PARRY = 1.3, BLOCK = 1.3, DEFENSE = 1.3, HPS = 1.3, MIT = 1.3,
               STR = 0.8, AP = 0.8, CRIT = 0.8, HIT = 0.8, DPS = 0.8, PDPS = 0.8, WDPS = 0.8 },
}
local wcache, wkey = nil, nil
local function Weights(spec)
  local base = W[spec]
  local level = UnitLevel("player") or 1
  if spec == "PROT" and level >= 58 then base = W.PROT60 end
  if spec ~= "PROT" then return base end
  local hp = UnitHealthMax and UnitHealthMax("player") or 0
  local _, armor = UnitArmor and UnitArmor("player")
  local db, dm = UnitDefense and UnitDefense("player")
  local focus = AskAHDB and AskAHDB.focus
  local key = table.concat({ level, hp, armor or 0, (db or 0) + (dm or 0), focus or "" }, ":")
  if wkey == key then return wcache end
  local w = {}
  for k, v in pairs(base) do w[k] = v end
  -- Armor: damage taken from same-level mobs is cut by A / (A + K). One armor
  -- adds HP / K effective health, one Stamina adds 10 * (A + K) / K, so
  -- armor is worth HP / (10 * (A + K)) Stamina.
  if hp and hp > 0 and armor then
    local K = (level < 60) and (400 + 85 * level) or (467.5 * level - 22167.5)
    w.ARMOR = w.STA * hp / (10 * (armor + K))
  end
  -- "% less damage taken" from stuns/slows/debuff procs: 1% is worth 1% of
  -- your health in Stamina (HP / 1000). Dodge is valued higher because a
  -- dodge also gives rage and Revenge.
  if hp and hp > 0 then w.MIT = w.STA * hp / 1000 end
  if level >= 58 and db then
    local def = db + (dm or 0)
    if def >= 440 then w.DEFENSE = 0.46 end
    local exp = GetExpertise and GetExpertise()
    if exp and exp >= 6.5 then w.EXP = 0 end
  end
  local f = FOCUS[focus or ""]
  if f then for k, m in pairs(f) do if w[k] then w[k] = w[k] * m end end end
  wcache, wkey = w, key
  return w
end

-- GetItemStats keys -> our short names
local KEYS = {
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
  ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
  RESISTANCE0_NAME = "ARMOR", ITEM_MOD_EXTRA_ARMOR_SHORT = "ARMOR",
  ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
  ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEFENSE",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
  ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_EXPERTISE_RATING_SHORT = "EXP", ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
  ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
  ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
  ITEM_MOD_HEALTH_REGEN_SHORT = "HP5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
  RESISTANCE1_NAME = "RES", RESISTANCE2_NAME = "RES", RESISTANCE3_NAME = "RES", RESISTANCE4_NAME = "RES",
  RESISTANCE5_NAME = "RES", RESISTANCE6_NAME = "RES",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}
local LABEL = { STR = "Str", AGI = "Agi", STA = "Sta", INT = "Int", SPI = "Spi", ARMOR = "Armor",
  BLOCKVALUE = "Block value", BLOCK = "Block", DODGE = "Dodge", PARRY = "Parry", DEFENSE = "Defense",
  AP = "AP", RAP = "Ranged AP", HIT = "Hit", CRIT = "Crit", SP = "Spell power", HEAL = "Healing",
  MP5 = "MP5", EXP = "Expertise", DPS = "DPS",
  PDPS = "proc DPS", WDPS = "extra swing DPS", HPS = "heal/sec", MIT = "% less damage taken", THREAT = "% threat", RES = "resistance", HASTE = "Haste" }
local SHOW_ORDER = { "DPS", "STR", "AGI", "STA", "INT", "SPI", "AP", "ARMOR", "BLOCKVALUE", "BLOCK",
  "DODGE", "PARRY", "HIT", "CRIT", "SP", "HEAL", "DEFENSE", "EXP", "PDPS", "WDPS", "HPS", "MIT", "THREAT", "HASTE" }

-------------------------------------------------------------------------------
-- Spec
-------------------------------------------------------------------------------
local function OffhandIsShield()
  local link = GetInventoryItemLink("player", 17)
  if not link then return false end
  local equipLoc = select(9, try(GII, link))
  return equipLoc == "INVTYPE_SHIELD"
end

local function MainhandIs2H()
  local link = GetInventoryItemLink("player", 16)
  if not link then return false end
  return select(9, try(GII, link)) == "INVTYPE_2HWEAPON"
end

function T.Spec()
  local forced = AskAHDB and AskAHDB.spec
  if forced and forced ~= "auto" and W[forced] then return forced end
  local _, class = UnitClass("player")
  if class == "WARRIOR" then
    if OffhandIsShield() then return "PROT" end
    if MainhandIs2H() then return "ARMS" end
    return "FURY"
  elseif class == "ROGUE" then return "ROGUE"
  elseif class == "HUNTER" then return "HUNTER"
  elseif class == "MAGE" or class == "WARLOCK" then return "CASTER"
  elseif class == "PRIEST" then return "HEALER"
  else return "HYBRID" end -- Paladin, Shaman, Druid: change with /askah spec
end

local SPEC_NAMES = { PROT = "Prot", ARMS = "Arms", FURY = "Fury", ROGUE = "Rogue", HUNTER = "Hunter",
  CASTER = "Caster", HEALER = "Healer", HYBRID = "Hybrid" }
T.SPEC_NAMES = SPEC_NAMES

-------------------------------------------------------------------------------
-- Item stats and scoring
-------------------------------------------------------------------------------
local function RawStats(link)
  -- Blizzard API data first (random-suffix items excepted), then the game.
  local api = ns.Blizz and ns.Blizz.StatsFirst(link)
  if api then return api end
  local raw
  if C_Item and C_Item.GetItemStats then raw = try(C_Item.GetItemStats, link) end
  if not raw and GetItemStats then raw = try(GetItemStats, link) end
  local s = {}
  for k, v in pairs(raw or {}) do
    local key = KEYS[k]
    if key then s[key] = (s[key] or 0) + v end
  end
  -- Not loaded by the game yet: use Blizzard's API data (BlizzData.lua).
  if not next(s) and ns.Blizz then
    local id = link and tonumber(link:match("item:(%d+)"))
    local b = id and ns.Blizz.Stats(id)
    if b then return b end
  end
  return s
end

-- Plain stats plus the value of procs, Equip/Use effects (Effects.lua).
local function GameStats(link)
  local raw
  if C_Item and C_Item.GetItemStats then raw = try(C_Item.GetItemStats, link) end
  if not raw and GetItemStats then raw = try(GetItemStats, link) end
  local s = {}
  for k, v in pairs(raw or {}) do
    local key = KEYS[k]
    if key then s[key] = (s[key] or 0) + v end
  end
  return s
end
local function GetStats(link)
  local s = RawStats(link)
  -- Items only in Blizzard's Classic data: Forever may have changed them, so
  -- trust what the game itself says when it has the item loaded.
  if ns.Effects and link and ns.Effects.IsClassicData(link) then
    local g = GameStats(link)
    if next(g) then s = g end
  end
  local copy = {}
  for k, v in pairs(s) do copy[k] = v end
  if ns.Effects then ns.Effects.Normalize(copy, link) end
  if ns.Effects and link then ns.Effects.Add(copy, link, (copy.DPS or 0) > 0) end
  return copy
end

local function Score(stats, slot, spec, equipLoc)
  local w = Weights(spec)
  local sum = 0
  for k, v in pairs(stats) do
    local weight = w[k] or 0
    -- gear effects (Effects.lua): proc damage counts like weapon DPS, heals like
    -- Stamina (1 heal/sec ~ 3 Sta), mitigation % like Dodge %
    -- proc damage: threat but no rage, so a bit under weapon DPS for prot;
    -- extra swings (WDPS) are white hits and count fully
    if k == "PDPS" then weight = w.PDPS or w.DPS or 1
    elseif k == "WDPS" then weight = w.DPS or 1
    elseif k == "HPS" then weight = (w.STA or 0.4) * 3
    elseif k == "MIT" then weight = w.MIT or (w.DODGE or 0.3) * 12
    elseif k == "THREAT" then weight = w.THREAT or 0
    elseif k == "RES" then weight = w.RES or 0.03 end
    if k == "DPS" then
      if slot == 18 then
        weight = w.RDPS or 0.5          -- ranged: you mostly just pull with it
      elseif slot == 17 then
        weight = (spec == "FURY" or spec == "ROGUE") and (w.DPS * 0.5) or 0
      end
    end
    sum = sum + weight * v
  end
  return sum
end

-- equipLoc -> inventory slots it can go in
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Ask Mr. Robot / Pawn scale (Effects.lua). While PAWN is set, items are
-- scored with Pawn's value plus what Pawn can't value (procs, Use effects).
local PAWN
local function Extras(stats, slot, spec, equipLoc)
  local e = {}
  for k, v in pairs(stats) do
    if k == "PDPS" or k == "WDPS" or k == "HPS" or k == "MIT" or k == "THREAT" then e[k] = v
    elseif k:sub(1, 2) == "X_" then e[k:sub(3)] = (e[k:sub(3)] or 0) + v end
  end
  return Score(e, slot, spec, equipLoc)
end
local function ItemScore(stats, link, slot, spec, equipLoc)
  if PAWN then
    if not link then return 0 end
    local v = ns.Effects.PawnValue(link, PAWN.scale)
    if not v then PAWN.failed = true; return 0 end
    return v + Extras(stats, slot, spec, equipLoc) * PAWN.ratio
  end
  return Score(stats, slot, spec, equipLoc)
end

local function EquippedScore(slot, spec)
  local link = GetInventoryItemLink("player", slot)
  if not link then return 0, {}, nil end
  local equipLoc = select(9, try(GII, link))
  local st = GetStats(link)
  return ItemScore(st, link, slot, spec, equipLoc), st, link
end

local SetGain
-- Shift detail: how much each stat moves the score (in Stamina-sized points).
local function WhyText(new, old, slot, spec, equipLoc)
  local parts = {}
  local seen = {}
  for _, t in ipairs({ new, old }) do for k in pairs(t) do seen[k] = true end end
  for k in pairs(seen) do
    local d = (new[k] or 0) - (old[k] or 0)
    if d ~= 0 then
      local one = {}; one[k] = d
      local v = Score(one, slot, spec, equipLoc)
      if math.abs(v) >= 0.3 then parts[#parts + 1] = { k = k, v = v } end
    end
  end
  table.sort(parts, function(a, b) return math.abs(a.v) > math.abs(b.v) end)
  local out = {}
  for i = 1, math.min(#parts, 6) do
    local p = parts[i]
    out[#out + 1] = (p.v > 0 and GREEN or RED) .. ("%s %+.1f"):format(LABEL[p.k] or p.k, p.v) .. "|r"
  end
  return table.concat(out, ", ")
end

local function DeltaText(new, old)
  local parts = {}
  for _, k in ipairs(SHOW_ORDER) do
    local d = (new[k] or 0) - (old[k] or 0)
    if math.abs(d) >= 0.05 then
      local txt = (k == "DPS" or k == "PDPS" or k == "WDPS" or k == "HPS" or k == "MIT") and ("%+.1f"):format(d) or ("%+d"):format(d > 0 and math.floor(d + 0.5) or -math.floor(-d + 0.5))
      parts[#parts + 1] = (d > 0 and GREEN or RED) .. txt .. " " .. LABEL[k] .. "|r"
    end
    if #parts >= 5 then break end
  end
  return table.concat(parts, ", ")
end

-- Set bonuses gained (or lost) by swapping link in for what's in that slot.
SetGain = function(link, oldLink, slot, spec, equipLoc)
  if not (ns.Effects and link) then return 0 end
  local d, text = ns.Effects.SetDelta(link, oldLink, function(st) return Score(st, slot, spec, equipLoc) * (PAWN and PAWN.ratio or 1) end)
  return d or 0, text
end

-- Rings and trinkets: compare with BOTH equipped ones, say which one to replace.
local PAIR_NAMES = { [11] = "ring 1", [12] = "ring 2", [13] = "trinket 1", [14] = "trinket 2" }
local function ItemName(link)
  return (link and try(GII, link)) or (link and link:match("%[(.-)%]")) or "?"
end
local function PairAdvice(link, equipLoc, slots, spec, newStats)
  local specName = SPEC_NAMES[spec] or spec
  local kind = equipLoc == "INVTYPE_TRINKET" and "trinket" or "ring"
  for _, s in ipairs(slots) do
    if not GetInventoryItemLink("player", s) then
      return { GREEN .. ("Upgrade: your %s slot is empty. Wear it!|r"):format(PAIR_NAMES[s]) }, true, 100
    end
  end
  local newScore = ItemScore(newStats, link, slots[1], spec, equipLoc)
  local cmp = {}
  for i, s in ipairs(slots) do
    local sc, st, l = EquippedScore(s, spec)
    local setGain = SetGain(link, l, s, spec, equipLoc)
    cmp[i] = { slot = s, score = sc, stats = st, name = ItemName(l), diff = newScore + setGain - sc,
               pct = (newScore + setGain - sc) / math.max(sc, 1) * 100 }
  end
  -- Replace the weaker of the two.
  local weak, strong = cmp[1], cmp[2]
  if cmp[2].score < cmp[1].score then weak, strong = cmp[2], cmp[1] end
  local lines = {}
  if weak.diff > 0.5 and weak.pct >= 3 then
    lines[1] = GREEN .. ("Upgrade for %s: replace %s (+%d%%).|r"):format(specName, weak.name, weak.pct + 0.5)
  elseif weak.diff < -0.5 and weak.pct <= -3 then
    lines[1] = RED .. ("Worse than both of your %ss for %s.|r"):format(kind, specName)
  else
    lines[1] = YELLOW .. ("About the same as your weaker %s (%s).|r"):format(kind, weak.name)
  end
  for _, c in ipairs({ cmp[1], cmp[2] }) do
    local col = c.diff > 0.5 and GREEN or (c.diff < -0.5 and RED or YELLOW)
    local mark = (c == weak and weak.diff > 0.5) and (GREY .. " (replace this one)|r") or ""
    lines[#lines + 1] = DETAIL .. GREY .. ("   vs %s (%s):|r %s%+d%%|r%s"):format(c.name, PAIR_NAMES[c.slot], col, c.pct + (c.pct >= 0 and 0.5 or -0.5), mark)
  end
  local delta = DeltaText(newStats, weak.stats)
  if delta ~= "" then lines[#lines + 1] = "   " .. delta .. GREY .. " (vs " .. weak.name .. ")|r" end
  local why = WhyText(newStats, weak.stats, weak.slot, spec, equipLoc)
  if why ~= "" then lines[#lines + 1] = DETAIL .. GREY .. "   Score: |r" .. why end
  local lost = ns.Effects and ns.Effects.EnchantText(GetInventoryItemLink("player", weak.slot))
  if lost and weak.diff > 0.5 then
    lines[#lines + 1] = "   " .. YELLOW .. "You'd lose the enchant on " .. weak.name .. ": " .. lost .. " (counted)|r"
  end
  return lines, weak.diff > 0.5 and weak.pct >= 3, weak.pct
end

-- Returns verdict line(s) for gear.
local GearAdviceCore
-- Uses your Ask Mr. Robot scale in Pawn when there is one, else AskAH's weights.
local function GearAdvice(link, equipLoc, newStats)
  local E = ns.Effects
  local scale, label = E and E.PawnScale()
  if scale and link then
    local spec = T.Spec()
    local w = Weights(spec)
    local per = E.PawnPer(scale, "STA")
    local ratio = (per and w.STA and w.STA > 0) and (per / w.STA) or nil
    if not ratio then
      per = E.PawnPer(scale, "STR")
      ratio = (per and w.STR and w.STR > 0) and (per / w.STR) or 1
    end
    PAWN = { scale = scale, ratio = ratio }
    local ok, lines, up, pct = pcall(GearAdviceCore, link, equipLoc, newStats)
    local failed = PAWN.failed
    PAWN = nil
    if ok and lines and not failed then
      lines[#lines + 1] = DETAIL .. GREY .. "   Scored with your Ask Mr. Robot scale (" .. tostring(label) .. ") + procs.|r"
      return lines, up, pct
    end
  end
  return GearAdviceCore(link, equipLoc, newStats)
end

GearAdviceCore = function(link, equipLoc, newStats)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  local spec = T.Spec()
  newStats = newStats or GetStats(link)

  -- Hovering something you're wearing?
  for _, s in ipairs(slots) do
    if GetInventoryItemLink("player", s) == link then
      return { GREY .. "You're wearing this.|r" }
    end
  end

  if spec == "PROT" and equipLoc == "INVTYPE_2HWEAPON" then
    return { YELLOW .. "Two-hander: not for Prot (you'd lose your shield).|r",
             GREY .. "Fine as an off-spec weapon for solo questing.|r" }
  end
  if spec == "PROT" and slots[1] == 17 and equipLoc ~= "INVTYPE_SHIELD" then
    return { YELLOW .. "Not a shield: Prot keeps the shield in the off hand.|r" }
  end

  local slot, oldScore, oldStats
  if #slots == 2 then
    -- Rings / trinkets: check against both you have on and say which to replace.
    return PairAdvice(link, equipLoc, slots, spec, newStats)
  else
    slot = slots[1]
    oldScore, oldStats = EquippedScore(slot, spec)
    -- 2H replaces main hand + off hand
    if equipLoc == "INVTYPE_2HWEAPON" then
      local s17, st17 = EquippedScore(17, spec)
      oldScore = oldScore + s17
      local merged = {}
      for k, v in pairs(oldStats) do merged[k] = v end
      for k, v in pairs(st17) do if k ~= "DPS" then merged[k] = (merged[k] or 0) + v end end
      oldStats = merged
    end
  end

  local newScore = ItemScore(newStats, link, slot, spec, equipLoc)
  local setGain, setText = SetGain(link, GetInventoryItemLink("player", slot), slot, spec, equipLoc)
  newScore = newScore + setGain
  local lines = {}
  local specName = SPEC_NAMES[spec] or spec
  local pct = 100
  if not GetInventoryItemLink("player", slot) then
    lines[1] = GREEN .. "Upgrade: that slot is empty. Wear it!|r"
  else
    local diff = newScore - oldScore
    pct = diff / math.max(oldScore, 1) * 100
    if pct >= 3 and diff > 0.5 then
      lines[1] = GREEN .. ("Upgrade for %s: +%d%%|r"):format(specName, pct + 0.5)
    elseif pct <= -3 and diff < -0.5 then
      lines[1] = RED .. ("Worse than yours for %s (%d%%).|r"):format(specName, pct - 0.5)
    else
      lines[1] = YELLOW .. ("About the same as yours for %s (%+d%%).|r"):format(specName, pct + (pct >= 0 and 0.5 or -0.5))
    end
  end
  local delta = DeltaText(newStats, oldStats)
  if delta ~= "" then lines[#lines + 1] = "   " .. delta end
  local why = WhyText(newStats, oldStats, slot, spec, equipLoc)
  if why ~= "" then lines[#lines + 1] = DETAIL .. GREY .. "   Score: |r" .. why end
  if setText then lines[#lines + 1] = "   " .. (setGain > 0 and GREEN or RED) .. setText .. " (bonus counted)|r" end
  local lost = ns.Effects and ns.Effects.EnchantText(GetInventoryItemLink("player", slot))
  if lost and lost ~= ns.Effects.EnchantText(link) then
    lines[#lines + 1] = "   " .. YELLOW .. "You'd lose your enchant: " .. lost .. " (counted)|r"
  end
  if spec == "PROT" and (newStats.DEFENSE or 0) > 0 and (newStats.STR or 0) == 0 and (newStats.STA or 0) == 0 then
    lines[#lines + 1] = DETAIL .. GREY .. "   Defense: more dodge, parry, block and enemy misses.|r"
  end
  return lines, pct >= 3 and newScore > oldScore + 0.5, pct
end

-------------------------------------------------------------------------------
-- Upgrade check for an item the game may not have loaded (AH feed listings,
-- quest rewards), from Blizzard's API data. Returns pct, lines (nil if it's
-- not gear you can use).
-------------------------------------------------------------------------------
local ARMOR_OK = {
  WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
  ROGUE = { [1] = 1, [2] = 1 }, DRUID = { [1] = 1, [2] = 1 },
  PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}
local WEAPON_OK = {
  WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
  PALADIN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
  HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [18] = 1 },
  ROGUE = { [2] = 1, [3] = 1, [4] = 1, [7] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
  PRIEST = { [4] = 1, [10] = 1, [15] = 1, [19] = 1 }, MAGE = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
  WARLOCK = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 }, SHAMAN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
  DRUID = { [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
}
function T.CanUse(itemID, level)
  local B = ns.Blizz
  local it = B and B.Item(itemID)
  if not it then return nil end
  local _, class, classID = UnitClass("player")
  level = level or UnitLevel("player") or 1
  if it.req > level then return false, ("needs level %d"):format(it.req) end
  if it.classID == 4 and it.subID and it.subID >= 1 and it.subID <= 6 and ARMOR_OK[class] then
    local need = ARMOR_OK[class][it.subID]
    if not need then return false, "wrong armor type" end
    if need > level then return false, ("armor type at %d"):format(need) end
  elseif it.classID == 2 and WEAPON_OK[class] and it.subID and not WEAPON_OK[class][it.subID] then
    return false, "wrong weapon type"
  end
  local g = B.Gear(itemID)
  if g and g.classes and classID and not g.classes[classID] then return false, "other class" end
  return true
end

-- /askah gear: writes what AskAH sees about your gear into AskAHDB.gearDump
-- (saved on /reload or logout) so wrong picks can be checked line by line.
function T.Snapshot()
  local spec = T.Spec()
  local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\001", "")) end
  local function copy(st) local o = {} for k, v in pairs(st or {}) do o[k] = math.floor(v * 100 + 0.5) / 100 end return o end
  local _, armor = UnitArmor("player")
  local d = { time = time and time() or 0, level = UnitLevel("player"), spec = spec, hp = UnitHealthMax("player"),
              armor = armor, focus = AskAHDB.focus, pawn = ns.Effects and ns.Effects.PawnScale() or nil,
              weights = copy(Weights(spec)), equipped = {}, bags = {} }
  for slot = 1, 18 do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local st = GetStats(link)
      local equipLoc = select(9, try(GII, link))
      d.equipped[#d.equipped + 1] = { slot = slot, link = link, name = ItemName(link), stats = copy(st),
        score = math.floor(Score(st, slot, spec, equipLoc) * 100 + 0.5) / 100,
        lines = ns.Effects and ns.Effects.Lines(link) or nil }
    end
  end
  local C = C_Container
  local nSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local getLink = (C and C.GetContainerItemLink) or GetContainerItemLink
  for bag = 0, 4 do
    for i = 1, (nSlots and nSlots(bag) or 0) do
      local link = getLink and getLink(bag, i)
      local equipLoc = link and select(9, try(GII, link))
      if link and equipLoc and SLOTS[equipLoc] then
        local st = GetStats(link)
        local lines, up, pct = GearAdvice(link, equipLoc, st)
        local out = {}
        for _, l in ipairs(lines or {}) do out[#out + 1] = plain(l) end
        d.bags[#d.bags + 1] = { link = link, name = ItemName(link), equipLoc = equipLoc, stats = copy(st),
          score = math.floor(Score(st, SLOTS[equipLoc][1], spec, equipLoc) * 100 + 0.5) / 100,
          upgrade = up and true or false, pct = pct, advice = out,
          lines = ns.Effects and ns.Effects.Lines(link) or nil }
      end
    end
  end
  AskAHDB.gearDump = d
  return #d.equipped, #d.bags
end

function T.UpgradeFor(itemID)
  local B = ns.Blizz
  local it = B and B.Item(itemID)
  if not it or not SLOTS[it.equipLoc] then return nil end
  if not T.CanUse(itemID) then return nil end
  local link = select(2, try(GII, itemID)) or select(2, B.ItemInfo(itemID))
  local stats = GetStats(link)
  if not next(stats) then stats = B.Stats(itemID) or {} end
  local lines, up, pct = GearAdvice(link, it.equipLoc, stats)
  if not lines then return nil end
  return up and pct or nil, lines
end

-------------------------------------------------------------------------------
-- Can you wear it? Read the tooltip itself: the game colors anything you
-- can't use (level, armor type, weapon skill, class) in red.
-------------------------------------------------------------------------------
local function TooltipHasRed(tooltip)
  local name = tooltip:GetName()
  if not name then return false end
  for i = 2, tooltip:NumLines() do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = _G[name .. "Text" .. side .. i]
      if fs and fs:IsShown() and fs:GetText() then
        local r, g, b = fs:GetTextColor()
        if r and r > 0.95 and g < 0.2 and b < 0.2 then return true end
      end
    end
  end
  return false
end

local function TooltipHasText(tooltip, text)
  local name = tooltip:GetName()
  if not name or not text then return false end
  for i = 2, math.min(tooltip:NumLines(), 6) do
    local fs = _G[name .. "TextLeft" .. i]
    if fs and fs:GetText() == text then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- Build the lines
--
-- Layout (kept short on purpose):
--   AskAH                     <verdict: auction it / vendor it / keep it>
--   Faction AH   price (you get X)       <- best place to sell in green
--   Neutral AH   price (you get X)
--   Vendor       price
--   gear verdict + stat changes
--   profession / recipe / crafting lines
--   "Shift: more detail" (listing counts, data age, guide steps, set bonuses)
-- Each section can be turned off in Esc > Options > AddOns > AskAH.
-------------------------------------------------------------------------------

-- Section on/off switches (AskAHDB.tt) and detail mode.
function T.Opt(key)
  local tt = AskAHDB and AskAHDB.tt
  return not (tt and tt[key] == false)
end
function T.ShowDetail()
  return (AskAHDB and AskAHDB.ttDetail == "always") or (IsShiftKeyDown and IsShiftKeyDown()) or false
end

function T.Add(tooltip, link)
  if not link or not AskAHDB then return end
  if AskAHDB.tooltip == false then return end
  local itemID = tonumber(link:match("item:(%d+)"))
  if not itemID then return end

  local name, _, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, _, _, bindType = try(GII, link)
  if not name then return end -- not cached yet; the tooltip refreshes once it is
  sellPrice = sellPrice or 0

  local detail = T.ShowDetail()
  local hidden = false -- did we leave something out that Shift would show?
  local out = {}       -- { left, right } or { text }
  local function Line(text) out[#out + 1] = { text } end
  local function Pair(l, r) out[#out + 1] = { l, r } end
  local function More(text) if detail then Line(text) else hidden = true end end

  local soulbound = (ITEM_SOULBOUND and TooltipHasText(tooltip, ITEM_SOULBOUND)) or bindType == 1

  -- 1. Prices: your faction AH, the goblin (neutral) AH and the vendor.
  local CUT = { faction = 0.95, neutral = 0.85 } -- neutral AH keeps 15%
  local fe = ns.Data.Prices("faction")[itemID]
  local ne = ns.Data.Prices("neutral")[itemID]
  local fNet = fe and math.floor(fe.p * CUT.faction)
  local nNet = ne and math.floor(ne.p * CUT.neutral)
  local bestWhere, bestNet
  if fNet and (not nNet or fNet >= nNet) then bestWhere, bestNet = "faction", fNet
  elseif nNet then bestWhere, bestNet = "neutral", nNet end
  local ahPrice = bestNet and (bestNet / CUT[bestWhere])

  -- Which pays most once the cut, lost deposits and the chance it doesn't
  -- sell count (SellAdvice.lua): faction AH, neutral AH or vendor.
  local sell = (not soulbound) and ns.Sell and select(2, pcall(ns.Sell.Advise, itemID, 1)) or nil
  if type(sell) ~= "table" then sell = nil end
  local bestPlace
  if sell and sell.bestWhere then bestPlace = sell.bestWhere
  elseif bestNet and (sellPrice == 0 or bestNet > sellPrice) then bestPlace = bestWhere
  elseif sellPrice > 0 then bestPlace = "vendor" end

  if T.Opt("prices") then
    local function AHRow(label, key, e, net, cutText)
      local col = (bestPlace == key) and GREEN or "|cffffffff"
      local right = Money(e.p) .. GREY .. " (you get " .. "|r" .. Money(net) .. GREY .. ")|r"
      Pair(col .. label .. "|r", right)
      if detail then
        Pair(GREY .. "   " .. cutText .. " cut|r", GREY .. ("%d listed, seen %s|r"):format(e.q or 0, ns.Data.Ago(e.t)))
      else hidden = true end
    end
    if not soulbound then
      if fe then AHRow("Faction AH", "faction", fe, fNet, "5%") end
      if ne then AHRow("Neutral AH", "neutral", ne, nNet, "15%") end
      if not fe and not ne then Pair("Auction house", GREY .. "no price seen yet|r") end
    end
    -- How likely it is to sell (SellAdvice.lua): the chance per listing at each
    -- AH, with the main reason; Shift shows the full breakdown.
    if not soulbound and sell and next(sell.ah) then
      local bits = {}
      for _, w in ipairs({ "faction", "neutral" }) do
        local x = sell.ah[w]
        if x then
          local col = x.chance >= 0.7 and GREEN or (x.chance >= 0.35 and YELLOW or RED)
          bits[#bits + 1] = ("%s %s%d%%|r"):format(w == "neutral" and "neutral" or "faction", col, math.floor(x.chance * 100 + 0.5))
        end
      end
      Pair("Chance to sell", table.concat(bits, GREY .. " / |r"))
      local x = sell.ah[sell.bestWhere] or sell.ah.faction or sell.ah.neutral
      local why = {}
      if x.spd then why[#why + 1] = ("sells ~%s/day"):format(x.spd >= 10 and ("%d"):format(x.spd) or ("%.1f"):format(x.spd)) end
      if x.listed then why[#why + 1] = ("%d listed"):format(x.listed) end
      if x.why and x.throughN and x.throughN >= 3 then
        why[#why + 1] = ("%d%% of its cheapest listings sell"):format(math.floor(x.why.pQueue * 100 + 0.5))
      end
      if x.sold + x.unsold > 0 then why[#why + 1] = ("you sold %d of %d"):format(x.sold, x.sold + x.unsold) end
      if #why == 0 then why[1] = "no sales data yet" end
      Line(GREY .. "   " .. table.concat(why, ", ") .. (" (%s confidence)"):format(x.conf) .. "|r")
      if detail then
        local all = ns.Sell.Lines(itemID, 1, false)
        for i = 2, #(all or {}) do Line(all[i]) end
      else hidden = true end
    end
    if sellPrice > 0 then
      Pair(((bestPlace == "vendor") and GREEN or "|cffffffff") .. "Vendor|r", Money(sellPrice))
    elseif not soulbound then
      Pair("Vendor", GREY .. "can't sell to a vendor|r")
    end
  end

  -- 2. Gear: only say something when it matters (can't wear it, or how it
  -- compares with what you have on).
  local isGear = SLOTS[equipLoc] ~= nil
  local isUpgrade = false
  if isGear and T.Opt("gear") then
    local level = UnitLevel("player")
    if minLevel and minLevel > level then
      Line(YELLOW .. ("Wearable at level %d (%d to go).|r"):format(minLevel, minLevel - level))
    elseif TooltipHasRed(tooltip) then
      Line(RED .. "You can't use this.|r")
      isGear = false
    end
    if isGear then
      local lines, up = GearAdvice(link, equipLoc)
      isUpgrade = up
      for _, l in ipairs(lines or {}) do
        if l:sub(1, 1) == DETAIL then More(l:sub(2)) else Line(l) end
      end
    end
  end

  -- 3. Professions. Only items on the WoW Forever leveling guides
  -- (wow-professions.com and Wowhead) count, from your skill up to 300.
  local needed, uses = false, nil
  local okG, errG = pcall(function()
    if not T.Opt("prof") then
      -- still work out "needed" so the verdict stays right
      local guide = ns.Prof and ns.Prof.GuideNeeds and ns.Prof.GuideNeeds(itemID)
      if guide and guide[1] then needed, uses = true, { { prof = guide[1].prof } } end
      return
    end
    local shown = {}
    local guide = ns.Prof and ns.Prof.GuideNeeds and ns.Prof.GuideNeeds(itemID)
    for _, g in ipairs(guide or {}) do
      needed = true
      uses = uses or { { prof = g.prof } }
      shown[g.prof] = true
      Pair(YELLOW .. g.prof .. "|r" .. GREY .. (" (you're %d)|r"):format(g.skill), ("need ~%d to 300"):format(g.total))
      if detail then
        if g.sites and g.sites[1] then
          local bits = {}
          for _, s in ipairs(g.sites) do bits[#bits + 1] = s.total and ("%s ~%d"):format(s.site, s.total) or s.site end
          Line(GREY .. "   guides: " .. table.concat(bits, ", ") .. "|r")
        end
        for i = 1, math.min(#g.steps, 4) do
          local s2 = g.steps[i]
          Line(GREY .. ("   %d-%d %s: ~%d|r"):format(s2.from, s2.to, s2.rec, s2.qty) ..
            (s2.now and (GREEN .. " (you're here)|r") or ""))
        end
        if #g.steps > 4 then Line(GREY .. ("   +%d more steps|r"):format(#g.steps - 4)) end
      else
        local now
        for _, s2 in ipairs(g.steps or {}) do if s2.now then now = s2 break end end
        if now then Line(GREY .. ("   now: %s, ~%d|r"):format(now.rec, now.qty)) end
        hidden = true
      end
    end

    -- 3a. A recipe item (Pattern:, Plans:, ...): is what it teaches on a guide?
    local rec
    if ns.Prof and ns.Prof.GuideRecipe then rec = ns.Prof.GuideRecipe(name) end
    if rec then
      if #rec == 0 then
        Line(GREY .. "Recipe: not used on the leveling guides.|r")
      else
        for _, g in ipairs(rec) do
          local tag
          if g.mine and g.past then tag = GREY .. "past it|r"
          elseif g.mine then
            tag = ((g.skill or 0) >= g.from) and (GREEN .. "learn it now|r") or (GREEN .. ("keep for skill %d|r"):format(g.from))
            needed = true
            uses = uses or { { prof = g.prof } }
          else tag = GREY .. "not your profession|r" end
          Pair(("Recipe: %s %d-%d"):format(g.prof, g.from, g.to), tag)
          More(GREY .. ("   ~%d crafts (%s)|r"):format(g.crafts, table.concat(g.sites, ", ")))
        end
      end
    end

    -- 3b. Other professions whose leveling guide uses it.
    local all = ns.Prof and ns.Prof.GuideAll and ns.Prof.GuideAll(itemID)
    if all and #all > 0 then
      local names = {}
      for _, g in ipairs(all) do
        if not shown[g.prof] then
          names[#names + 1] = g.prof
          if detail then
            local tag = (g.mine and g.past) and " (yours, past it)" or (g.mine and " (yours)" or "")
            Line(GREY .. ("   %s ~%d, skill %d-%d (%s)%s|r"):format(g.prof, g.total, g.from, g.to, table.concat(g.sites, ", "), tag))
          end
        end
      end
      if #names > 0 then
        if detail then table.insert(out, #out - #names + 1, { GREY .. "Also on the leveling guides:|r" })
        else Line(GREY .. "Also on leveling guides: " .. table.concat(names, ", ") .. "|r"); hidden = true end
      end
    end
  end)
  if not okG and AskAHDB and AskAHDB.debug then ns.Print("guide error: " .. tostring(errG)) end

  -- 3c. Blizzard data: crafting cost, which recipes use it, item set.
  if ns.Blizz and T.Opt("craft") then
    local okB, blines, more = pcall(ns.Blizz.TooltipLines, itemID, detail)
    if okB and blines then for _, l in ipairs(blines) do Line(l) end end
    if okB and more then hidden = true end
  end

  -- 4. The verdict goes on the header line, so it's the first thing you read.
  local verdict, why
  if isUpgrade then
    verdict = GREEN .. "Keep: upgrade|r"
  elseif needed then
    verdict = GREEN .. "Keep: for " .. ((uses and uses[1].prof) or "a profession") .. "|r"
  elseif soulbound then
    verdict = sellPrice > 0 and (YELLOW .. "Vendor it|r") or (GREY .. "Soulbound|r")
  elseif sell and next(sell.ah) then
    if sell.bestWhere ~= "vendor" then
      local x = sell.ah[sell.bestWhere]
      verdict = GREEN .. ("Auction it (%s AH)|r"):format(sell.bestWhere)
      why = ("List at ~%s. With a %d%% sell chance, the cut and lost deposits it's worth ~%s, %s more than the vendor."):format(
        Money(x.price), math.floor(x.chance * 100 + 0.5), Money(math.floor(x.value)), Money(math.max(0, math.floor(x.value - sellPrice))))
    else
      verdict = YELLOW .. "Vendor it|r"
      local best = 0
      for _, x in pairs(sell.ah) do best = math.max(best, x.value) end
      why = ("The vendor's %s beats the AH's ~%s once the chance it doesn't sell counts."):format(Money(sellPrice), Money(math.floor(best)))
    end
    -- the most important part: say why without Shift
    Line(GREY .. why .. "|r"); why = nil
  elseif ahPrice then
    local net = bestNet
    if sellPrice == 0 or (net > sellPrice * 1.2 and net - sellPrice >= 500) then
      verdict = GREEN .. ("Auction it (%s AH)|r"):format(bestWhere)
      if sellPrice > 0 then why = ("Pays %s more than the vendor after the cut."):format(Money(net - sellPrice)) end
    else
      verdict = YELLOW .. "Vendor it|r"
      why = (net <= sellPrice) and "The vendor pays more than the AH after the cut." or "The AH barely beats the vendor."
    end
  elseif quality and quality >= 2 then
    verdict = GREY .. "Check the AH|r"
    why = "Green or better and tradeable. No AH price seen yet."
  elseif sellPrice > 0 then
    verdict = GREY .. "No AH price yet|r"
    why = "Scan the AH (/askah scan) to compare."
  end
  if why then More(GREY .. why .. "|r") end

  if #out == 0 and not verdict then return true end
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine(BLUE .. "AskAH|r", verdict or "", 1, 1, 1, 1, 1, 1)
  for _, l in ipairs(out) do
    if l[2] then tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
    else tooltip:AddLine(l[1], 1, 1, 1, true) end
  end
  if hidden and AskAHDB.ttHint ~= false then
    tooltip:AddLine(GREY .. "Hold Shift for more|r")
  end
  return true
end

-------------------------------------------------------------------------------
-- Hook item tooltips (not the comparison tooltips)
--
-- Plays nicely with Forever Mouse Tooltip and Questie, which hook the same
-- tooltips:
--   * we never call ClearLines/SetOwner, so Forever Mouse Tooltip keeps
--     control of the position (it re-anchors on OnSizeChanged by itself)
--   * on the modern path we don't call tooltip:Show(): on this client that
--     can taint the tooltip (Forever Mouse Tooltip notes the same)
--   * the game can re-run item postcalls on a tooltip that's already shown,
--     so we only add our lines once per tooltip until it's cleared
-------------------------------------------------------------------------------
local LinkFrom = function(tooltip, data)
  local link
  if tooltip.GetItem then
    local ok, _, l = pcall(tooltip.GetItem, tooltip)
    if ok then link = l end
  end
  if not link and data and type(data.hyperlink) == "string" then link = data.hyperlink end
  if not link and data and data.id then link = select(2, try(GII, data.id)) end
  if issecretvalue and link and issecretvalue(link) then return nil end
  return link
end

local done = {}  -- tooltip -> link we already added lines for

local function Handle(tooltip, data, legacy)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local link = LinkFrom(tooltip, data)
  if not link or done[tooltip] == link then return end
  local ok, err = pcall(T.Add, tooltip, link)
  if ok and err then
    done[tooltip] = link
    if legacy then tooltip:Show() end  -- classic-style tooltips must resize
  elseif AskAHDB and AskAHDB.debug then
    ns.Print("tooltip error: " .. tostring(err))
  end
end

for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
  if tt then tt:HookScript("OnTooltipCleared", function(self) done[self] = nil end) end
end

-- Same check Questie uses: some clients expose TooltipDataProcessor but
-- their tooltips still only fire the legacy scripts.
local usesTooltipData = type(GameTooltip.GetPrimaryTooltipData) == "function"
  and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
  and Enum and Enum.TooltipDataType

if usesTooltipData then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    Handle(tooltip, data, false)
  end)
else
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt then pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) Handle(self, nil, true) end) end
  end
end

-- Holding or letting go of Shift redraws the item tooltip so the extra
-- detail appears or disappears.
local modEv = CreateFrame("Frame")
modEv:RegisterEvent("MODIFIER_STATE_CHANGED")
modEv:SetScript("OnEvent", function(_, _, key)
  if not (key == "LSHIFT" or key == "RSHIFT") then return end
  if not AskAHDB or AskAHDB.tooltip == false or AskAHDB.ttDetail == "always" then return end
  local tt = GameTooltip
  if not tt or not tt:IsShown() or not done[tt] then return end
  done[tt] = nil
  if tt.RefreshData and pcall(tt.RefreshData, tt) then return end
  local owner = tt.GetOwner and tt:GetOwner()
  local onEnter = owner and owner.GetScript and owner:GetScript("OnEnter")
  if onEnter and owner:IsMouseOver() then pcall(onEnter, owner) end
end)
