-- Reward.lua
-- Works out a quest's rewards in detail and whether the quest is worth it for
-- you: XP for your level, gold, every item (upgrade check for your spec,
-- vendor / auction value), and how much effort it is (elite, dungeon, travel).
-- If AskAH is installed it reuses AskAH's auction prices and spec setting;
-- AskQuest works fine without it.
local _, ns = ...
local F = ns.F

local GREEN, RED, YELLOW, GREY, BLUE, ORANGE = "|cff33ff33", "|cffff4040", "|cffffd200", "|cff999999", "|cff33ccff", "|cffff8040"
local PURPLE = "|cffa335ee"

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h, i, j, k, l, m, n = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h, i, j, k, l, m, n end
end

-- WoW: Forever runs the modern client: C_Item.GetItemInfo is the reliable one.
local GII = function(x) local B = AskAHBlizzAPI; if B and B.GetItemInfo then return B.GetItemInfo(x) end return ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(x) end -- Blizzard API data first, then the game

---------------------------------------------------------------------------
-- Stat weights: same numbers as AskAH (Prot set from WoW Forever guides,
-- switching to PROT60 at level 58).
---------------------------------------------------------------------------
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
  ARMS = { STR = 1.0, AGI = 0.8, STA = 0.3, AP = 0.5, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01, SPI = 0.1, DPS = 8.0 },
  FURY = { STR = 1.0, AGI = 0.8, STA = 0.3, AP = 0.5, CRIT = 1.0, HIT = 1.2, ARMOR = 0.01, SPI = 0.1, DPS = 7.0 },
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
local SPEC_NAMES = { PROT = "Prot", ARMS = "Arms", FURY = "Fury", ROGUE = "Rogue", HUNTER = "Hunter",
  CASTER = "Caster", HEALER = "Healer", HYBRID = "Hybrid" }
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
  RESISTANCE5_NAME = "RES", RESISTANCE6_NAME = "RES", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}
local LABEL = { STR = "Str", AGI = "Agi", STA = "Sta", INT = "Int", SPI = "Spi", ARMOR = "Armor",
  BLOCKVALUE = "Block value", BLOCK = "Block", DODGE = "Dodge", PARRY = "Parry", DEFENSE = "Defense",
  AP = "AP", RAP = "Ranged AP", HIT = "Hit", CRIT = "Crit", SP = "Spell power", HEAL = "Healing", MP5 = "MP5", EXP = "Expertise", DPS = "DPS",
  PDPS = "proc DPS", WDPS = "extra swing DPS", HPS = "heal/sec", MIT = "% less damage taken", THREAT = "% threat", RES = "resistance", HASTE = "Haste" }
local SHOW_ORDER = { "DPS", "STR", "AGI", "STA", "INT", "SPI", "AP", "ARMOR", "BLOCKVALUE", "BLOCK",
  "DODGE", "PARRY", "HIT", "CRIT", "SP", "HEAL", "DEFENSE", "EXP", "PDPS", "WDPS", "HPS", "MIT", "THREAT", "HASTE" }
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- What each class can use (Classic rules). Armor subclass: 1 cloth, 2 leather,
-- 3 mail, 4 plate, 6 shield. Weapon subclasses per the item DB.
local ARMOR = {
  WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 }, PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
  ROGUE = { [1] = 1, [2] = 1 }, DRUID = { [1] = 1, [2] = 1 },
  PRIEST = { [1] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
}
local WEAPON = {
  WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
  PALADIN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [6] = 1, [7] = 1, [8] = 1 },
  HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [6] = 1, [7] = 1, [8] = 1, [10] = 1, [13] = 1, [15] = 1, [18] = 1 },
  ROGUE = { [2] = 1, [3] = 1, [4] = 1, [7] = 1, [13] = 1, [15] = 1, [16] = 1, [18] = 1 },
  PRIEST = { [4] = 1, [10] = 1, [15] = 1, [19] = 1 }, MAGE = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 },
  WARLOCK = { [7] = 1, [10] = 1, [15] = 1, [19] = 1 }, SHAMAN = { [0] = 1, [1] = 1, [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
  DRUID = { [4] = 1, [5] = 1, [10] = 1, [13] = 1, [15] = 1 },
}

local function ItemInfo(item)
  local name, link, quality, _, minLevel, _, _, _, equipLoc, _, sell, classID, subID, bind = try(GII, item)
  if not name then
    if type(item) == "number" and C_Item and C_Item.RequestLoadItemDataByID then try(C_Item.RequestLoadItemDataByID, item) end
    -- Not loaded by the game yet: Blizzard's API data from AskAH, if it has it.
    if type(item) == "number" and AskAHBlizzAPI then
      name, link, quality, _, minLevel, _, _, _, equipLoc, _, sell, classID, subID, bind = AskAHBlizzAPI.ItemInfo(item)
    end
    if not name then return nil end
  end
  return { name = name, link = link, quality = quality, minLevel = minLevel or 0, equipLoc = equipLoc,
           sell = sell or 0, classID = classID, subID = subID, bind = bind }
end

local function RawStats(link)
  -- Blizzard API data (from AskAH) first, random-suffix items excepted, then the game.
  local api = AskAHBlizzAPI and AskAHBlizzAPI.StatsFirst(link)
  if api then return api end
  local raw
  if C_Item and C_Item.GetItemStats then raw = try(C_Item.GetItemStats, link) end
  if not raw and GetItemStats then raw = try(GetItemStats, link) end
  local s = {}
  for k, v in pairs(raw or {}) do
    local key = KEYS[k]
    if key then s[key] = (s[key] or 0) + v end
  end
  if not next(s) and AskAHBlizzAPI then
    local id = link and tonumber(link:match("item:(%d+)"))
    local b = id and AskAHBlizzAPI.Stats(id)
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

local function Score(stats, slot, spec)
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
      if slot == 18 then weight = w.RDPS or 0.5
      elseif slot == 17 then weight = (spec == "FURY" or spec == "ROGUE") and (w.DPS * 0.5) or 0 end
    end
    sum = sum + weight * v
  end
  return sum
end

local function EquipLoc(link)
  return link and select(9, try(GII, link))
end

function ns.Spec()
  local forced = AskAHDB and AskAHDB.spec          -- AskAH's /askah spec setting, if you use AskAH
  if forced and forced ~= "auto" and W[forced] then return forced end
  local _, class = UnitClass("player")
  if class == "WARRIOR" then
    if EquipLoc(GetInventoryItemLink("player", 17)) == "INVTYPE_SHIELD" then return "PROT" end
    if EquipLoc(GetInventoryItemLink("player", 16)) == "INVTYPE_2HWEAPON" then return "ARMS" end
    return "FURY"
  elseif class == "ROGUE" then return "ROGUE"
  elseif class == "HUNTER" then return "HUNTER"
  elseif class == "MAGE" or class == "WARLOCK" then return "CASTER"
  elseif class == "PRIEST" then return "HEALER" end
  return "HYBRID"
end

-- Ask Mr. Robot / Pawn scale (Effects.lua): Pawn's value plus procs and Use
-- effects Pawn can't value. Used only when every item involved has a value.
local PAWN
local function ItemScore(stats, link, slot, spec)
  if PAWN and link then
    local v = ns.Effects.PawnValue(link, PAWN.scale)
    if v then
      local e = {}
      for k, x in pairs(stats) do
        if k == "PDPS" or k == "WDPS" or k == "HPS" or k == "MIT" or k == "THREAT" then e[k] = x
        elseif k:sub(1, 2) == "X_" then e[k:sub(3)] = (e[k:sub(3)] or 0) + x end
      end
      return v + Score(e, slot, spec) * PAWN.ratio
    end
  end
  return Score(stats, slot, spec)
end
local function PawnFor(spec, links)
  local E = ns.Effects
  local scale = E and E.PawnScale()
  if not scale then return nil end
  for _, l in ipairs(links) do if l and not E.PawnValue(l, scale) then return nil end end
  local w = Weights(spec)
  local per = E.PawnPer(scale, "STA")
  local ratio = (per and w.STA and w.STA > 0) and per / w.STA
  if not ratio then per = E.PawnPer(scale, "STR"); ratio = (per and w.STR and w.STR > 0) and per / w.STR or 1 end
  return { scale = scale, ratio = ratio }
end

local function EquippedScore(slot, spec)
  local link = GetInventoryItemLink("player", slot)
  if not link then return 0, {}, nil end
  local st = GetStats(link)
  return ItemScore(st, link, slot, spec), st, link
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

-- AH price from AskAH's saved scans, if AskAH is installed and has seen the item.
local function AHPrice(itemID)
  if not (AskAHDB and AskAHDB.prices and itemID) then return nil end
  local key = (GetRealmName() or "?") .. " - " .. (UnitFactionGroup("player") or "?")
  local e = AskAHDB.prices[key] and AskAHDB.prices[key][itemID]
  return e and e.p
end

-- AskAH's AH-or-vendor advice for one item, cached a minute.
local adviceCache = {}
function ns.SellAdvice(itemID)
  if not (AskAHSell and AskAHSell.Advise and itemID) then return nil end
  local c = adviceCache[itemID]
  local now = time()
  if c and now - c.t < 60 then return c.a end
  local ok, a = pcall(AskAHSell.Advise, itemID, 1)
  a = ok and a or nil
  adviceCache[itemID] = { t = now, a = a }
  return a
end

-- What one item sells for, and where: { value, where = vendor|faction|neutral,
-- ah, chance, bound } or nil while the item's info is loading. Cached a minute.
local saleCache = {}
function ns.ItemSaleValue(itemID)
  local now = time()
  local c = saleCache[itemID]
  if c and now - c.t < 60 then return c.v end
  local info = ItemInfo(itemID)
  if not info then return nil end
  local v = { value = info.sell, where = (info.sell > 0) and "vendor" or nil, bound = (info.bind == 1) }
  if not v.bound then
    local adv = ns.SellAdvice(itemID)
    if adv then
      local best = math.floor(adv.best or 0)
      if adv.bestWhere and adv.bestWhere ~= "vendor" and best > info.sell then
        v.value, v.where = best, adv.bestWhere
        local x = adv.ah and adv.ah[adv.bestWhere]
        if x then v.ah, v.chance = x.price, x.chance end
      end
    else
      local ah = AHPrice(itemID)
      if ah and math.floor(ah * 0.95) > info.sell then v.ah, v.value, v.where = ah, math.floor(ah * 0.95), "faction" end
    end
  end
  saleCache[itemID] = { t = now, v = v }
  return v
end

-- What a quest's item rewards are worth in gold if you sell them: the best
-- choice reward plus every fixed one. Returns copper, the best choice's
-- evaluation, and whether some item info is still loading.
function ns.RewardGold(id)
  local choices, fixed = ns.QuestRewards(id)
  local best, bestR, loading = 0, nil, false
  for _, itemID in ipairs(choices) do
    local r = ns.ItemSaleValue(itemID)
    if not r then loading = true elseif (r.value or 0) > best then best, bestR = r.value, r end
  end
  local total = best
  for _, itemID in ipairs(fixed) do
    local r = ns.ItemSaleValue(itemID)
    if not r then loading = true else total = total + (r.value or 0) end
  end
  return total, bestR, loading
end

-- Gold plus what the rewards sell for (used by "most gold").
function ns.TotalGold(id, q)
  local g = ns.Gold(id, q or ns.quests[id])
  local items = ns.RewardGold(id)
  return math.max(g or 0, 0) + (items or 0), g, items
end

-- Full verdict for one item. Returns a table.
function ns.EvaluateItem(itemID)
  local info = ItemInfo(itemID)
  if not info then return { loading = true, id = itemID } end
  local r = { id = itemID, info = info, value = info.sell }
  local level = UnitLevel("player") or 1
  local _, class = UnitClass("player")

  -- Can you use it?
  if info.classID == 4 and ARMOR[class] and info.subID and info.subID >= 1 then
    local need = ARMOR[class][info.subID]
    if not need and info.subID <= 6 then r.cantUse = "your class can't wear this armor"
    elseif need and need > level then r.cantUse = ("you can wear this armor type at %d"):format(need) end
  elseif info.classID == 2 and WEAPON[class] and info.subID and not WEAPON[class][info.subID] then
    r.cantUse = "your class can't use this weapon type"
  end
  if not r.cantUse and info.minLevel > level then r.later = info.minLevel end

  -- Value: soulbound rewards are worth their vendor price. Others use AskAH's
  -- sell advice (AH cut, lost deposits, the chance it actually sells, and
  -- which AH), or plain AH price minus 5% if AskAH's advice isn't there.
  local sv = ns.ItemSaleValue(itemID)
  if sv then r.bound, r.value, r.sellWhere, r.ah, r.chance = sv.bound, sv.value, sv.where, sv.ah, sv.chance end

  -- Upgrade check
  local slots = SLOTS[info.equipLoc or ""]
  if slots and not r.cantUse then
    local spec = ns.Spec()
    r.spec = SPEC_NAMES[spec]
    local newStats = GetStats(info.link)
    local links = { info.link }
    for _, sl in ipairs(slots) do links[#links + 1] = GetInventoryItemLink("player", sl) end
    if info.equipLoc == "INVTYPE_2HWEAPON" then links[#links + 1] = GetInventoryItemLink("player", 17) end
    PAWN = PawnFor(spec, links)
    r.amr = PAWN and true or nil
    if spec == "PROT" and info.equipLoc == "INVTYPE_2HWEAPON" then
      r.note = "two-hander: not for Prot"
    elseif spec == "PROT" and slots[1] == 17 and info.equipLoc ~= "INVTYPE_SHIELD" then
      r.note = "not a shield: Prot keeps the shield"
    else
      local slot, oldScore, oldStats
      if #slots == 2 then
        -- Rings / trinkets: compare with both you wear; the weaker one is the one to replace.
        local s1, st1, l1 = EquippedScore(slots[1], spec)
        local s2, st2, l2 = EquippedScore(slots[2], spec)
        local ns1 = ItemScore(newStats, info.link, slots[1], spec)
        local function nm(l) return l and (try(GII, l) or l:match("%[(.-)%]")) end
        local function pct(old) return math.floor((ns1 - old) / math.max(old, 1) * 100 + 0.5) end
        r.vs = {}
        if l1 then r.vs[#r.vs + 1] = { nm(l1), pct(s1) } end
        if l2 then r.vs[#r.vs + 1] = { nm(l2), pct(s2) } end
        if not l1 then slot, oldScore, oldStats = slots[1], 0, {}
        elseif not l2 then slot, oldScore, oldStats = slots[2], 0, {}
        elseif s1 <= s2 then slot, oldScore, oldStats = slots[1], s1, st1; r.replace = nm(l1)
        else slot, oldScore, oldStats = slots[2], s2, st2; r.replace = nm(l2) end
      else
        slot = slots[1]
        oldScore, oldStats = EquippedScore(slot, spec)
        if info.equipLoc == "INVTYPE_2HWEAPON" then
          local s17 = EquippedScore(17, spec)
          oldScore = oldScore + s17
        end
      end
      local newScore = ItemScore(newStats, info.link, slot, spec)
      if ns.Effects and info.link then
        local d, txt = ns.Effects.SetDelta(info.link, GetInventoryItemLink("player", slot), function(st) return Score(st, slot, spec) * (PAWN and PAWN.ratio or 1) end)
        newScore = newScore + (d or 0); r.setText = txt
      end
      if not GetInventoryItemLink("player", slot) then
        r.upgrade, r.gain = true, 100
      else
        local diff = newScore - oldScore
        r.gain = math.floor(diff / math.max(oldScore, 1) * 100 + 0.5)
        r.upgrade = diff > 0.5 and r.gain >= 3
        r.worse = diff < -0.5 and r.gain <= -3
      end
      r.delta = DeltaText(newStats, oldStats)
      if r.amr then r.delta = (r.delta ~= "" and (r.delta .. ", ") or "") .. "AMR scale" end
      if r.setText then r.delta = (r.delta ~= "" and (r.delta .. ", ") or "") .. r.setText end
      local lost = ns.Effects and ns.Effects.EnchantText(GetInventoryItemLink("player", slot))
      if lost then r.delta = (r.delta ~= "" and (r.delta .. ", ") or "") .. "loses your enchant (" .. lost .. ")" end
    end
  end
  PAWN = nil
  return r
end

---------------------------------------------------------------------------
-- XP you'd actually get (same rules Questie uses, from cMaNGOS)
---------------------------------------------------------------------------
function ns.EffectiveXP(xp, qLevel)
  local level = UnitLevel("player") or 1
  local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
  if level >= maxLevel then return 0 end
  local mult = 2 * (qLevel - level) + 20
  if mult < 1 then mult = 1 elseif mult > 10 then mult = 10 end
  xp = xp * mult / 10
  if xp <= 100 then xp = 5 * math.floor((xp + 2) / 5)
  elseif xp <= 500 then xp = 10 * math.floor((xp + 5) / 10)
  elseif xp <= 1000 then xp = 25 * math.floor((xp + 12) / 25)
  else xp = 50 * math.floor((xp + 25) / 50) end
  return xp
end

---------------------------------------------------------------------------
-- Rewards for a quest: live from the quest window when we have it,
-- then what we learned earlier, then the database.
---------------------------------------------------------------------------
local function ItemID(link) return link and tonumber(link:match("item:(%d+)")) end

function ns.LiveRewards(kind) -- kind "quest" (giver window) or "log" (selected quest log entry)
  local choices, fixed = {}, {}
  if kind == "quest" then
    for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do choices[#choices + 1] = ItemID(GetQuestItemLink("choice", i)) end
    for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do fixed[#fixed + 1] = ItemID(GetQuestItemLink("reward", i)) end
  else
    for i = 1, (GetNumQuestLogChoices and GetNumQuestLogChoices() or 0) do choices[#choices + 1] = ItemID(GetQuestLogItemLink("choice", i)) end
    for i = 1, (GetNumQuestLogRewards and GetNumQuestLogRewards() or 0) do fixed[#fixed + 1] = ItemID(GetQuestLogItemLink("reward", i)) end
  end
  return choices, fixed
end

function ns.Learn(id, choices, fixed)
  if not id or id == 0 then return end
  AskQuestDB.rewards = AskQuestDB.rewards or {}
  if #choices > 0 or #fixed > 0 then AskQuestDB.rewards[id] = { choices, fixed } end
end

local function Rewards(id)
  -- Blizzard API data first, then what the game showed you (quest log or
  -- quest window), then cMaNGOS. A source that lists no items doesn't win
  -- over one that does (the API leaves some quests' items out).
  local api = ns.blizzRewards and ns.blizzRewards[id]
  local learned = AskQuestDB.rewards and AskQuestDB.rewards[id]
  local db = ns.rewards[id]
  for _, r in ipairs({ api or false, learned or false, db or false }) do
    if r and (#(r[1] or {}) > 0 or #(r[2] or {}) > 0) then return r[1] or {}, r[2] or {}, true end
  end
  -- the game itself said "no items" (or the bundled data has the quest);
  -- Blizzard's API listing none isn't trusted alone: it leaves out the items
  -- of many quests (most of the Riverglades ones, for example)
  if (AskQuestDB.noItems and AskQuestDB.noItems[id]) or db then return {}, {}, true end
  return {}, {}, false, api and "api-empty" or nil
end
ns.QuestRewards = Rewards

---------------------------------------------------------------------------
-- Where an NPC is: zone, coordinates, and how far / which way from you.
---------------------------------------------------------------------------
local DIRS = { "east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast" }
function ns.MapName(map, fallback)
  local info = map and map > 0 and C_Map and C_Map.GetMapInfo and try(C_Map.GetMapInfo, map)
  return (info and info.name) or fallback or "?"
end

-- Returns "Zone (x, y)" and "250 yards northeast of you" (or nil if far away).
function ns.Where(map, x, y, fallbackZone)
  local zone = ns.MapName(map, fallbackZone)
  if not x or x <= 0 then return zone .. GREY .. " (spot unknown)|r" end
  local text = ("%s (%.1f, %.1f)"):format(zone, x, y)
  local away
  if C_Map and C_Map.GetPlayerMapPosition and map and map > 0 then
    local pos = try(C_Map.GetPlayerMapPosition, map, "player")
    local px, py
    if pos and pos.GetXY then px, py = pos:GetXY() end
    if px and py and (px > 0 or py > 0) then
      local dx, dy = x / 100 - px, y / 100 - py
      local w, h
      if C_Map.GetMapWorldSize then w, h = try(C_Map.GetMapWorldSize, map) end
      local dir = DIRS[(math.floor((math.deg(math.atan2(-dy * (h or 1), dx * (w or 1))) + 22.5) / 45) % 8) + 1]
      if w and w > 0 and h and h > 0 then
        local yards = math.sqrt((dx * w) ^ 2 + (dy * h) ^ 2)
        if yards < 15 then away = "right here"
        else away = ("%s yards %s of you"):format(ns.Commas(math.floor(yards / 10 + 0.5) * 10), dir) end
      else
        away = dir .. " of you"
      end
    else
      away = "not in your zone"
    end
  end
  return text, away
end

-- Lines describing who gives the quest and who takes it back.
function ns.GiverLines(q, id)
  local out = {}
  if not q then return out end
  local zone = ns.zones[q[F.ZONE]]
  local inLog = ns.InLog and ns.InLog(id)
  if q[F.GIVER] > 0 then
    local where, away = ns.Where(q[F.GMAP], q[F.GX], q[F.GY], zone)
    out[#out + 1] = { BLUE .. "Quest giver:|r " .. YELLOW .. ns.givers[q[F.GIVER]] .. "|r" .. (inLog and GREY .. " (you have this quest)|r" or "") }
    out[#out + 1] = { "    " .. where .. (away and (GREY .. ", " .. away .. "|r") or "") }
  else
    out[#out + 1] = { BLUE .. "Quest giver:|r " .. GREY .. "starts from an item or object|r" }
  end
  if q[F.ENDER] > 0 then
    local where, away = ns.Where(q[F.EMAP], q[F.EX], q[F.EY], zone)
    local same = q[F.ENDER] == q[F.GIVER]
    out[#out + 1] = { BLUE .. "Turn in to:|r " .. YELLOW .. ns.givers[q[F.ENDER]] .. "|r" .. (same and GREY .. " (same NPC)|r" or "") }
    if not same then out[#out + 1] = { "    " .. where .. (away and (GREY .. ", " .. away .. "|r") or "") } end
  end
  return out
end

---------------------------------------------------------------------------
-- The verdict
---------------------------------------------------------------------------
local function ItemLine(r, isChoice, best)
  if r.loading then return GREY .. "  (loading item info - hover again)|r" end
  local i = r.info
  local color = (i.link and i.link:match("|c(%x%x%x%x%x%x%x%x)")) or "ffffffff"
  local name = "|c" .. color .. i.name .. "|r"
  local verdict
  if r.cantUse then verdict = RED .. "can't use: " .. r.cantUse .. "|r"
  elseif r.note then verdict = YELLOW .. r.note .. "|r"
  elseif r.upgrade then verdict = GREEN .. ("UPGRADE for %s +%d%%"):format(r.spec, r.gain) .. (r.replace and (", replace " .. r.replace) or "") .. "|r"
  elseif r.worse then verdict = GREY .. (r.vs and #r.vs == 2 and "worse than both of yours (%d%%)" or "worse than yours (%d%%)"):format(r.gain) .. "|r"
  elseif r.spec then verdict = GREY .. "about the same as yours|r"
  else verdict = GREY .. "not gear|r" end
  if r.later then verdict = verdict .. ORANGE .. (" (usable at %d)"):format(r.later) .. "|r" end
  local val
  if r.sellWhere == "faction" or r.sellWhere == "neutral" then
    val = ("sell at the %s AH: ~%s%s"):format(r.sellWhere, ns.Money(r.value),
      r.chance and (GREY .. (" (%d%% sell chance)"):format(math.floor(r.chance * 100 + 0.5)) .. "|r") or "")
  elseif (r.value or 0) > 0 then
    val = (r.bound and "soulbound, vendor " or "vendor it: ") .. ns.Money(r.value)
  else val = GREY .. "no sale value|r" end
  local delta = r.delta
  if r.vs and #r.vs == 2 then
    local parts = {}
    for _, v in ipairs(r.vs) do
      parts[#parts + 1] = ("vs %s %s%+d%%|r"):format(v[1] or "?", v[2] > 0 and GREEN or (v[2] < 0 and RED or YELLOW), v[2])
    end
    delta = table.concat(parts, ", ") .. ((delta and delta ~= "") and ("; " .. delta) or "")
  end
  return ("%s%s %s - %s, %s"):format(best and (GREEN .. "> |r") or "  ", name, isChoice and "" or GREY .. "(always)|r", verdict, val), delta
end

-- Works out everything about a quest for you. live = rewards read from an
-- open quest window ({ choices, fixed, money, xp, title, level }) or nil.
function ns.Assess(id, live)
  local q = ns.quests[id]
  local a = { id = id, q = q }
  local level = UnitLevel("player") or 1
  a.level = level
  a.name = q and q[F.NAME] or (live and live.title) or ("Quest " .. id)
  a.qLevel = q and q[F.LVL] or (live and live.level) or level
  a.baseXP = (q and q[F.XP]) or (live and live.xp) or 0
  a.xp = (live and live.xp and live.xp > 0) and live.xp or ns.EffectiveXP(a.baseXP, a.qLevel)
  a.gold = (live and live.money) or (q and ns.Gold(id, q)) or -1
  local need = UnitXPMax and UnitXPMax("player") or 0
  a.pct = (need and need > 0) and (a.xp / need * 100) or 0

  local choices, fixed, known, why
  if live then choices, fixed, known = live.choices or {}, live.fixed or {}, true
  else choices, fixed, known, why = Rewards(id) end
  a.choices, a.fixed, a.known, a.unknownWhy = choices, fixed, known, why

  local bestValue, bestIdx, bestUpgrade = 0, nil, nil
  a.evals, a.fixedEvals = {}, {}
  for idx, itemID in ipairs(choices) do
    local r = ns.EvaluateItem(itemID)
    a.evals[idx] = r
    if r.loading then a.loading = true
    elseif r.upgrade and (not bestUpgrade or r.gain > a.evals[bestUpgrade].gain) then bestUpgrade = idx
    elseif (r.value or 0) > bestValue then bestValue, bestIdx = r.value, idx end
  end
  a.pick, a.bestUpgrade = bestUpgrade or bestIdx, bestUpgrade
  a.fixedValue = 0
  for idx, itemID in ipairs(fixed) do
    local r = ns.EvaluateItem(itemID)
    a.fixedEvals[idx] = r
    if r.loading then a.loading = true else
      a.fixedValue = a.fixedValue + (r.value or 0)
      if r.upgrade and not a.fixedUpgrade then a.fixedUpgrade = r end
    end
  end

  -- Effort
  local effort, why = 1.0, {}
  local kind = q and q[F.KIND] or 0
  if kind == 1 then effort = effort * 1.5; why[#why + 1] = "elite (bring a friend)" end
  if kind == 2 then effort = effort * 2.5; why[#why + 1] = "dungeon (needs a group)" end
  if q and q[F.TRAVEL] == 1 then effort = effort * 1.25; why[#why + 1] = "turn-in is in another zone" end
  local guideBonus = 1
  if ns.Guide then effort, guideBonus = ns.Guide.Adjust(q, level, effort, why) end   -- Guide.lua
  local here = ns.CurrentZone()
  a.here = q and here and q[F.ZONE] == here
  if q and here and not a.here then effort = effort * 1.15; why[#why + 1] = "not in this zone" end
  a.effort, a.effortWhy = effort, why
  a.tooHigh = q and q[F.REQ] > level

  -- Score: % of a level in XP + gold/items scaled to your level + upgrades
  local itemCopper = (a.pick and a.evals[a.pick] and a.evals[a.pick].value or 0) + a.fixedValue
  a.copper = math.max(a.gold, 0) + itemCopper
  local goldPts = a.copper / math.max(level * level * 5, 50)
  local upgradePts = (bestUpgrade or a.fixedUpgrade) and 4 or 0
  a.score = (a.pct + goldPts + upgradePts) / effort * guideBonus
  a.onGuide = guideBonus > 1
  -- The chain leads into a dungeon quest: important, rank it up (like an upgrade, at least "Worth it").
  a.leadsTo = q and ns.DungeonImportant and ns.DungeonImportant(id, level)
  if a.leadsTo then a.score = math.max(a.score + 4, 3.5) end

  if a.tooHigh then a.tier, a.tierKey = ORANGE .. "Not yet: you can take it at level " .. q[F.REQ] .. "|r", "later"
  elseif a.leadsTo then a.tier, a.tierKey = PURPLE .. "IMPORTANT - leads to a dungeon quest|r", "important"
  elseif a.score >= 6 then a.tier, a.tierKey = GREEN .. "GREAT - do it|r", "great"
  elseif a.score >= 3.5 then a.tier, a.tierKey = GREEN .. "Worth it|r", "worth"
  elseif a.score >= 1.5 then a.tier, a.tierKey = YELLOW .. "OK if you're nearby|r", "ok"
  else a.tier, a.tierKey = RED .. "Skip it|r", "skip" end
  return a
end

-- One short line on why a quest is good (or not) for you, for the chart and chat.
function ns.WhyShort(id)
  local a = ns.Assess(id)
  local parts = {}
  if a.tooHigh then parts[#parts + 1] = "take at " .. a.q[F.REQ] end
  if a.leadsTo then parts[#parts + 1] = PURPLE .. "leads to " .. ns.DungeonName(a.leadsTo) .. "|r|cffcccccc" end
  if a.pct >= 0.5 then parts[#parts + 1] = ("%.0f%% of a level"):format(a.pct)
  elseif a.xp > 0 then parts[#parts + 1] = ("%.1f%% of a level"):format(a.pct) end
  if a.bestUpgrade then
    local r = a.evals[a.bestUpgrade]
    parts[#parts + 1] = ("upgrade: %s +%d%%"):format(r.info.name, r.gain) .. (r.replace and (" (replaces " .. r.replace .. ")") or "")
  elseif a.fixedUpgrade then
    parts[#parts + 1] = ("upgrade: %s +%d%%"):format(a.fixedUpgrade.info.name, a.fixedUpgrade.gain)
  end
  if a.copper > 0 then parts[#parts + 1] = ns.Money(a.copper) end
  if a.here then parts[#parts + 1] = "in this zone" end
  if a.q and a.q[F.KIND] == 1 then parts[#parts + 1] = "elite" end
  if a.q and a.q[F.KIND] == 2 then parts[#parts + 1] = "dungeon" end
  if a.q and a.q[F.TRAVEL] == 1 then parts[#parts + 1] = "travel" end
  return table.concat(parts, ", "), a
end

-- Returns list of tooltip lines { left, right } plus loading flag and pick.
function ns.QuestReport(id, live)
  local a = ns.Assess(id, live)
  local q = a.q
  local lines = {}
  local function add(l, rt) lines[#lines + 1] = { l, rt } end

  add(YELLOW .. a.name .. "|r", GREY .. "level " .. a.qLevel .. "|r")
  if q and ns.IsDone(id) then add(GREEN .. "You've already done this quest.|r") end
  for _, l in ipairs(ns.GiverLines(q, id)) do add(l[1]) end
  if q then add(" ") end
  local xpText = (a.xp > 0) and (ns.Commas(a.xp) .. " XP" .. GREY .. (" (%.1f%% of your level)"):format(a.pct) .. "|r") or (GREY .. "no XP for you|r")
  if q and a.xp < a.baseXP then xpText = xpText .. ORANGE .. " reduced: quest is low for you|r" end
  add("XP", xpText)
  add("Gold", ns.Money(a.gold))

  if #a.choices > 0 then add(BLUE .. "Choose one of:|r") end
  for idx in ipairs(a.choices) do
    local l, delta = ItemLine(a.evals[idx], true, idx == a.pick)
    add(l)
    if delta and delta ~= "" and (a.evals[idx].upgrade or a.evals[idx].vs) then add("      " .. delta) end
  end
  for idx in ipairs(a.fixed) do
    local l, delta = ItemLine(a.fixedEvals[idx], false, false)
    add(l)
    if delta and delta ~= "" and (a.fixedEvals[idx].upgrade or a.fixedEvals[idx].vs) then add("      " .. delta) end
  end
  if not a.known then
    add(GREY .. (a.unknownWhy == "api-empty"
      and "Item rewards not listed in Blizzard's data. AskQuest reads them once the quest is in your log, or when you open it.|r"
      or "Item rewards unknown until the quest is in your log or you open it once.|r"))
  end
  if #a.choices == 0 and #a.fixed == 0 and a.known then add(GREY .. "No item rewards.|r") end

  add(" ")
  add("Worth it?", a.tier)
  local reasons = {}
  if a.pct > 0 then reasons[#reasons + 1] = ("%.1f%% of a level"):format(a.pct) end
  if a.copper > 0 then reasons[#reasons + 1] = ns.Money(a.copper) .. " total value" end
  if a.bestUpgrade then reasons[#reasons + 1] = GREEN .. "has an upgrade for you|r"
  elseif a.fixedUpgrade then reasons[#reasons + 1] = GREEN .. "gives an upgrade|r" end
  if a.here then reasons[#reasons + 1] = "in this zone" end
  if a.leadsTo then
    add(PURPLE .. "Important: this chain leads to the dungeon quest|r")
    add("    " .. PURPLE .. ns.DungeonName(a.leadsTo) .. "|r" .. GREY .. (" [%d]"):format(ns.quests[a.leadsTo][F.LVL]) .. "|r")
  end
  if #reasons > 0 then add(GREY .. "Why: " .. table.concat(reasons, ", ") .. "|r") end
  if a.tooHigh then a.effortWhy[#a.effortWhy + 1] = RED .. "you can take it at " .. q[F.REQ] .. "|r" end
  if #a.effortWhy > 0 then add(GREY .. "Effort: " .. table.concat(a.effortWhy, ", ") .. "|r") end
  local pr = a.pick and a.evals[a.pick]
  if pr and pr.info then
    add(GREEN .. "Pick: " .. pr.info.name .. (a.bestUpgrade and " (upgrade)" or " (sells for the most)") .. "|r")
  end
  local chain = ns.ChainLines and ns.ChainLines(id, true)
  if chain then for _, l in ipairs(chain) do add(l) end end
  return lines, a.loading, a.pick
end
-- Compact reward lines for one quest, for other addons' tooltips (Questie's
-- map icons, see QuestieTip.lua). Returns lines { left, right }, loading.
function ns.RewardSummary(id)
  local a = ns.Assess(id)
  local lines = {}
  local function add(l, r) lines[#lines + 1] = { l, r } end
  add(YELLOW .. a.name .. "|r", a.tier)
  local bits = {}
  if a.xp > 0 then bits[#bits + 1] = ns.Commas(a.xp) .. " XP" end
  if a.gold and a.gold > 0 then bits[#bits + 1] = ns.Money(a.gold) end
  if #bits > 0 then add("    " .. table.concat(bits, ", ")) end
  if #a.choices > 0 then add("    " .. BLUE .. "Choose one of:|r") end
  for idx in ipairs(a.choices) do add("    " .. (ItemLine(a.evals[idx], true, idx == a.pick))) end
  for idx in ipairs(a.fixed) do add("    " .. (ItemLine(a.fixedEvals[idx], false, false))) end
  if not a.known then add("    " .. GREY .. "Item rewards unknown until the quest is in your log or you open it once.|r")
  elseif #a.choices == 0 and #a.fixed == 0 then add("    " .. GREY .. "No item rewards.|r") end
  return lines, a.loading
end

---------------------------------------------------------------------------
-- Our own tooltip frame, so we never fight with GameTooltip users
-- (Forever Mouse Tooltip, Questie, AskAH).
---------------------------------------------------------------------------
local tip = CreateFrame("GameTooltip", "AskQuestTip", UIParent, "GameTooltipTemplate")
tip:SetFrameStrata("TOOLTIP")
local current -- { id, owner, anchor, live }

local function Fill()
  if not current then return end
  local lines, loading = ns.QuestReport(current.id, current.live)
  tip:ClearLines()
  for i, l in ipairs(lines) do
    if l[2] then tip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
    else tip:AddLine(l[1], 1, 1, 1, i > 1) end
  end
  tip:Show()
  current.loading = loading
end

-- owner: frame to anchor to; anchor: "ANCHOR_RIGHT" or a point table {point, rel, relPoint, x, y}
function ns.ShowQuestTip(id, owner, anchor, live)
  if AskQuestDB.info == false and not (owner and owner.isAskQuestRow) then return end
  if not id then return end
  tip:SetOwner(owner or UIParent, type(anchor) == "string" and anchor or "ANCHOR_NONE")
  if type(anchor) == "table" then
    tip:ClearAllPoints()
    tip:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4] or 0, anchor[5] or 0)
  end
  current = { id = id, owner = owner, anchor = anchor, live = live }
  Fill()
end

function ns.HideQuestTip(owner)
  if not current or (owner and current.owner ~= owner) then return end
  current = nil
  tip:Hide()
end

-- Item data arrives later the first time: refresh the open report.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function()
  if current and current.loading and tip:IsShown() then Fill() end
end)
