-- Knowledge.lua (the gold and leveling guide; was the Q&A list)
-- The Guide tab: only gold routes and leveling guides, picked for your
-- character (level, class, professions).
--
-- Sources (read Nov 2026):
--   Warcraft Tavern WoW Forever guides (zones, dungeons, XP, all 9 class leveling guides)
--     https://www.warcrafttavern.com/forever/guides/leveling/
--     https://www.warcrafttavern.com/forever/guides/dungeons/
--     https://www.warcrafttavern.com/forever/guides/<class>-leveling/
--   Skycoach and MeinMMO WoW Forever gold guides (Nov 2026)
--   Warcraft Tavern Classic gold guide (farm spots; Classic values, so marked)
--   Wowhead / wow-professions Forever profession guides (the steps in Guides.lua)
-- Icy Veins and Mobalytics Forever pages could not be read.
local _, ns = ...

local R = {}
ns.Routes = R

local function Lvl()
  local l = UnitLevel and UnitLevel("player")
  if l and l > 0 then return l end
  local s = ns.Data and ns.Data.Char().stats
  return (s and s.level) or 1
end

local function Class()
  local _, c = UnitClass("player")
  return c or "WARRIOR"
end

---------------------------------------------------------------------------
-- Leveling zones and dungeons (Alliance; Warcraft Tavern Forever)
---------------------------------------------------------------------------
R.ZONES = {
  { 1, 10, "Elwynn Forest, Dun Morogh, Teldrassil" },
  { 10, 20, "Westfall, Loch Modan, Darkshore (10); Redridge Mountains (15); Ashenvale (18)" },
  { 20, 30, "Wetlands, Duskwood, Hillsbrad Foothills (20); Thousand Needles (25)" },
  { 30, 35, "Arathi Highlands, Alterac Mountains, Stranglethorn Vale, Desolace" },
  { 35, 40, "Riverglades (new), Dustwallow Marsh, Badlands, Swamp of Sorrows, Feralas" },
  { 40, 45, "Shen'dralas (new), Tanaris, The Hinterlands (40); Searing Gorge (43)" },
  { 45, 50, "Azshara, Felwood, Blasted Lands (45); Un'Goro Crater (48)" },
  { 50, 55, "Burning Steppes, Western Plaguelands (50); Winterspring, Eastern Plaguelands (53)" },
  { 55, 61, "Silithus, Deadwind Pass (55); Mount Hyjal (60, new)" },
}

-- { min, max, name, where, new }
R.DUNGEONS = {
  { 13, 20, "Hall of Thanes", "Ironforge", true },
  { 17, 26, "Deadmines", "Westfall" },
  { 15, 24, "Wailing Caverns", "The Barrens" },
  { 20, 30, "Shadowfang Keep", "Silverpine Forest" },
  { 24, 32, "Blackfathom Deeps", "Ashenvale" },
  { 24, 32, "The Stockade", "Stormwind" },
  { 26, 33, "Excavation Site: Wetlands", "Wetlands", true },
  { 28, 35, "City of Dalaran", "Alterac Mountains (key from Southshore)", true },
  { 29, 38, "Gnomeregan", "Dun Morogh" },
  { 29, 38, "Razorfen Kraul", "The Barrens" },
  { 30, 38, "Scarlet Graveyard", "Tirisfal Glades" },
  { 33, 41, "Scarlet Library", "Tirisfal Glades" },
  { 35, 42, "The Drowned City", "Stranglethorn Vale", true },
  { 36, 44, "Scarlet Armory", "Tirisfal Glades" },
  { 37, 46, "Razorfen Downs", "The Barrens" },
  { 38, 46, "Scarlet Cathedral", "Tirisfal Glades" },
  { 40, 47, "Krol'Dok Stronghold", "Riverglades (key at 40)", true },
  { 41, 51, "Uldaman", "Badlands" },
  { 44, 54, "Zul'Farrak", "Tanaris" },
  { 46, 55, "Maraudon", "Desolace" },
  { 48, 55, "Alcaz Prison", "Dustwallow Marsh", true },
  { 50, 60, "Sunken Temple", "Swamp of Sorrows" },
  { 52, 60, "Blackrock Depths", "Blackrock Mountain" },
  { 54, 60, "Dire Maul East", "Feralas" },
  { 55, 60, "Lower Blackrock Spire", "Blackrock Mountain" },
  { 55, 60, "Blackmaw Hold", "Azshara", true },
  { 56, 60, "Dire Maul West / North", "Feralas" },
  { 58, 60, "Shaper's Terrace", "Un'Goro Crater", true },
  { 58, 60, "Stratholme, Scholomance", "Plaguelands" },
  { 59, 60, "Upper Blackrock Spire", "Blackrock Mountain" },
}

R.XP_TIPS = [=[Stack the Forever XP buffs: Cozy Sleeping Bag (up to 3 Well-Rested stacks, +1% each; chain starts at Burned-Out Remains, Westfall 37,50), Well Fed from Cooking food (+5% kill XP), and a Leatherworking Camp Tent (rested-style buff).
Quests more than 5 levels below you lose 10-20% XP per extra level, so skip gray quests.
Rested XP doubles kill XP only. A much higher-level group member cuts your XP, so dungeon boosting is weaker than in Classic.
Step-by-step quest routing: the RestedXP Guide and Questie addons support Forever.]=]

---------------------------------------------------------------------------
-- Class leveling guides (Warcraft Tavern Forever unless noted)
-- quests: { level, "text" }
---------------------------------------------------------------------------
local WT = "https://www.warcrafttavern.com/forever/guides/"
R.CLASSES = {
  WARRIOR = {
    url = WT .. "warrior-leveling/",
    spec = [=[All three trees level well. Arms is the classic choice; Protection is "incredibly strong now" for AoE pulls; Fury takes more damage.]=],
    talents = {
      { 10, 30, "Prot (Maxroll build): 10-14 Shield Specialization 5/5, 15-17 Improved Revenge 3/3, 18-19 Improved Thunder Clap 2/3, 20-21 Master of Defense 2/2, 22 Improved Thunder Clap 3/3, 23 Last Stand, 24 Improved Bloodrage 1/2, 25 Vanguard, 26 Improved Bloodrage 2/2, 27-29 Anticipation 3/5, 30 Concussion Blow." },
      { 31, 60, "Prot (Maxroll build): 31-33 Focused Rage 3/3, 34 Anticipation 4/5, 35-39 Bastion 5/5, 40 Shield Slam, 41-43 Improved Rend, 44-48 Deflection, 49-53 Cruelty, 54-55 Improved Charge, 56-60 Unbridled Wrath. Doing mostly dungeons: swap Improved Bloodrage/Anticipation points for Defiance 3/3." },
    },
    rotation = [=[Prot AoE: Charge in Defensive Stance (Vanguard), Thunder Clap, Demoralizing Shout, Shield Block + Revenge while tab-targeting, Cleave above 50-60 rage, Victory Rush under 90% HP. Eureka!, grenades and mouseover Taunt for big pulls.
Arms: Battle Shout, Charge, Overpower when lit, Mortal Strike, Rend if it will live, Spearing Strike on Giants/Dragonkin, Slam (Improved Slam), Heroic Strike with spare rage.
Fury: Bloodthirst, Whirlwind, Overpower, Heroic Strike.]=],
    tips = [=[Leveling stats (Prot): Stamina > Strength > weapon DPS > Hit > avoidance; ignore Defense until 58. Upgrade weapons often, keep Well Fed, and use cooldowns to pull bigger groups.]=],
    quests = {
      { 10, "Defensive Stance, Taunt, Sunder Armor (class trainer quest)" },
      { 20, "Brutal Hauberk or Fire Hardened Hauberk (Furen Longbeard, Stormwind, from 28)" },
      { 30, "The Affray (Fray Island, Barrens): Berserker Stance and Intercept" },
      { 30, "Whirlwind weapon chain: The Windwatcher -> Bath'rah (Alterac 80,67) -> Cyclonian (needs 8 Liferoot, 30 Bloodscalp Tusks, elemental charms from Arathi; lvl 40 elite)" },
    },
  },
  PALADIN = {
    url = WT .. "paladin-leveling/",
    spec = [=[Retribution is usually best early. From 30: Retribution, Protection, or Shockadin (Holy/Ret). The site's builds cover the level 30 beta; check the page for 60 builds.]=],
    talents = { { 1, 60, "26-point Ret, Prot or Shockadin build by 30 (35 without Legacy). Dual spec at 40." } },
    rotation = [=[Early: Seal of Righteousness, Judgement on approach, Holy Strike (from 6), then Judgement and Holy Strike on cooldown.
Ret: Seal of Command before pulls (two-hander, 20+). Prot: Seal of Fury, Judgement, Consecration, Holy Strike.]=],
    tips = [=[Retribution Aura for most leveling. Divine Protection / Blessing of Protection to save a pull. Buy new water about every 10 levels.]=],
    quests = {
      { 12, "The Tome of Divinity: Redemption" },
      { 20, "Bastion of Stormwind / Sense Undead, Verigan's Fist, Moonsilver Blade" },
    },
  },
  HUNTER = {
    url = WT .. "hunter-leveling/",
    spec = [=[Beast Mastery. Avoid Lone Wolf while leveling. Marksmanship and Survival are alternatives.]=],
    talents = { { 10, 60, "Beast Mastery toward Bestial Wrath first, then Marksmanship for Pathfinding and Efficiency." } },
    rotation = [=[Aspect of the Hawk, send pet, Auto Shot, Serpent Sting, Arcane Shot, Aimed Shot, Bestial Wrath, Rapid Fire. Wing Clip / Concussive Shot / Frost Trap if the pet loses aggro.
1-10: Aspect of the Monkey, Serpent Sting, Arcane Shot, Raptor Strike in melee.]=],
    tips = [=[Stats: Agility > Attack Power > Crit > Intellect. Mend Pet at 12. Aspect of the Cheetah dazes you when hit.]=],
    quests = { { 10, "Taming the Beast (pet)" } },
  },
  ROGUE = {
    url = WT .. "rogue-leveling/",
    spec = [=[Combat is the easiest (any weapon type, more energy). Assassination (Mutilate) and Subtlety (Ambush or Bleed) also work.]=],
    talents = { { 10, 60, "Subtlety (Ambush): 10 Opportunity, Master of Deception, Setup; 15 Improved Ambush, Dirty Deeds; 20 Premeditation, Serrated Blades, Initiative; 25 Ghostly Strike; 30 Preparation, Hemorrhage; 35 Boot Knife; 40 Thousand Cuts." } },
    rotation = [=[Combat: Stealth + Cheap Shot, Sinister Strike, Shank, Blade Flurry, Slice and Dice, Expose Armor, Eviscerate at 3-5 CP, Adrenaline Rush. Kick/Gouge, Vanish to escape.]=],
    tips = [=[Stats: Crit, Agility, AP, Strength, Stamina. Stealth openers slow leveling unless you play Ambush.]=],
    quests = { { 20, "Poisons: Mathias and the Defias, Klaven's Tower, The Touch of Zanzil (also unlocks Thistle Tea)" } },
  },
  PRIEST = {
    url = WT .. "priest-leveling/",
    spec = [=[Smite + wand early. At 30 pick Discipline (wand/Penance), Shadow, or Holy for dungeons.]=],
    talents = { { 20, 60, "Shadow: 20 Mind Flay, 25 Vampiric Embrace, 30 Silence, 40 Shadowform. Discipline: Penance after 30, Power Infusion at 40." } },
    rotation = [=[Disc: Power Word: Shield, Smite to pull, Shadow Word: Pain, Penance (30+), wand.
Shadow: Mind Blast on cooldown, SW:P, Devouring Plague (20+), Mind Flay.]=],
    tips = [=[Spirit first. Psychic Scream can pull more mobs. Dual spec at 40.]=],
    quests = {
      { 10, "Racial spell quest" },
      { 15, "Wailing Caverns: Sizzle Stick" },
      { 18, "Blackfathom Deeps: Gravestone Scepter" },
      { 20, "Racial spell quest" },
    },
  },
  SHAMAN = {
    url = WT .. "shaman-leveling/",
    spec = [=[Enhancement (melee) is the cleanest. Elemental works but runs low on mana. Restoration only for groups.]=],
    talents = { { 10, 60, "Enhancement to Stormstrike at 25. Elemental gets Lava Burst at 30. Dual spec at 40." } },
    rotation = [=[Lightning Shield + Windfury Weapon, Searing Totem + Strength of Earth, Lightning Bolt to pull, Flame Shock, Stormstrike on cooldown, Earth Shock filler, spend Maelstrom at 5.]=],
    tips = [=[Mana matters for every spec. Ghost Wolf at 20. Earth Shock interrupts.]=],
    quests = {
      { 4, "Stoneskin Totem" }, { 6, "Earthbind Totem" }, { 10, "Flame Shock / Searing Totem (Fire)" },
      { 20, "Call of Water (Water totem), Healing Stream" }, { 30, "Call of Air (Air totem)" },
    },
  },
  MAGE = {
    url = WT .. "mage-leveling/",
    spec = [=[Frost, with 7 early points in Arcane for Missile Barrage. Ice Lance has an 8 sec cooldown in Forever.]=],
    talents = { { 10, 60, "Arcane to Missile Barrage, then Frost: 20 Ice Lance, 25 Shatter/Ice Block, 30 Cold Snap/Fingers of Frost, 35 Winter's Chill, 40 Ice Barrier." } },
    rotation = [=[Frostbolt; Ice Lance on frozen targets or Fingers of Frost; Arcane Missiles on Missile Barrage. Frost Nova then Ice Lance. AoE: Frost Nova into Flamestrike.]=],
    tips = [=[Conjured food and water are free. AoE grinding was toned down in Forever.]=],
    quests = {
      { 10, "Speak with Belann / Mirror Lake / Mage-tastic Gizmonitor" },
      { 15, "Report to Jennea, Investigate the Blue Recluse, Manaweave Robe" },
      { 26, "High Sorcerer Andromath, Ur's Treatise on Shadow Magic, Astral Knot Garment" },
    },
  },
  WARLOCK = {
    url = WT .. "warlock-leveling/",
    spec = [=[Affliction, no respec needed. Destruction is for dungeons.]=],
    talents = {
      { 10, 30, "10-17 Improved Corruption 5/5, Suppression 3/5; 18-24 Unholy Power 5/5, Demonic Energies 2/2; 25-30 Improved Drains 3/3, Amplify Curse, Improved Bane of Agony 2/2." },
      { 31, 60, "31-40 Suppression, Pandemic 3/3, Improved Life Tap 1/2, Siphon Life (37), Soul Siphon 3/3; 41-47 Improved Life Tap 2/2, Shadow Mastery 5/5, Wrack (47); 48-60 Malevolence, Fel Concentration, Nightfall, Improved Shadow Bolt." },
    },
    rotation = [=[Bane of Agony to pull, Corruption, Immolate, Siphon Life (37+), Curse of the Elements (40+). Wand before 30, Drain Life after. Life Tap when health is above mana. Fear the second mob.]=],
    tips = [=[Voidwalker tanks, Sayaad for damage from 20. Make a Healthstone early. Dual spec at 40.]=],
    quests = {
      { 10, "Voidwalker" }, { 20, "Succubus/Incubus, The Orb of Soran'ruk" },
      { 30, "Felhunter" }, { 40, "Felsteed" }, { 60, "Dreadsteed" },
    },
  },
  DRUID = {
    url = WT .. "druid-leveling/",
    spec = [=[Feral cat. Balance (Multi-DoT or Eclipse) also works; Restoration is not for leveling.]=],
    talents = { { 10, 60, "Feral: Predatory Discipline (25), Leader of the Pack (30), Shifting Power (40)." } },
    rotation = [=[Cat: Thorns, Faerie Fire, Shifting Power under 50 energy, Rip at 4-5 CP, Ferocious Bite at 4-5 CP with 70+ energy, Rake, Claw (Shred from behind).
Bear: Faerie Fire, Lacerate, Demoralizing Roar, Swipe/Maul.]=],
    tips = [=[Prowl, Sprint and Travel Form save lots of time. Innervate and Barkskin often.]=],
    quests = {
      { 10, "Bear Form, Teleport: Moonglade" }, { 14, "Cure Poison" }, { 16, "Aquatic Form" }, { 20, "Cat Form" },
    },
  },
}

---------------------------------------------------------------------------
-- Gold routes by level. Spots marked (Classic) are from the Classic guides;
-- check they still work in Forever.
---------------------------------------------------------------------------
R.GOLD = {
  { 1, 20, {
    "Skin everything and sell stacks of 20 leather/hides; MeinMMO calls Skinning the best gold start in Forever.",
    "Loot and sell all cloth (Linen, Wool) in stacks; never vendor Rough/Coarse Stone.",
    "Fishing: Oily Blackmouth in Darkshore (skill 55) sells to alchemists (Classic).",
    "Buy bags early and keep a bank alt at the AH.",
  } },
  { 20, 30, {
    "Medium Leather: raptors at Whelgar's Excavation Site, Wetlands, 27+ (Classic).",
    "Firefin Snapper: Wetlands coast, Fishing 130 (Classic).",
    "Thousand Needles harpies: Vibrant Plumes sell for ~13-14s each.",
    "Incendicite Ore (Thelgen Rock, Wetlands): sell in stacks of 6 for the Dun Morogh quest.",
    "Copper/Tin bars and Coarse Stone always sell to new blacksmiths and engineers.",
  } },
  { 30, 40, {
    "Heavy Leather: Swamp of Sorrows, 37+ (Classic). Arathi and STV beasts on the way.",
    "Stonescale Eel: Stranglethorn coast, Fishing 205 (Classic); sells for Stonescale Oil.",
    "Riverglades and The Drowned City drop Forever-only BoEs. Don't equip unbound blues/epics you'll sell.",
    "Save ~100g for Apprentice Riding at 40 (Skycoach).",
  } },
  { 40, 50, {
    "Badlands earth elementals: Elemental Earth, Deepstone Salt (Classic).",
    "Tanaris / Feralas / Hinterlands beasts for Thick Leather; Mithril and Truesilver in Badlands and Hinterlands.",
    "Waylaid Crates (Forever): fill them with the asked-for mats and turn in to the Azeroth Commerce Authority for Merchant's Favor (recipes).",
  } },
  { 50, 60, {
    "Felwood Jadefire Satyrs: Felcloth, Demonic Runes, Runecloth (Classic).",
    "Winterfall furbolgs (Winterspring): Runecloth, E'ko, Juju (Classic).",
    "Rugged Leather in Eastern Plaguelands, 56+ (Classic). Thorium in Un'Goro, Plaguelands, Winterspring.",
    "Tyr's Hand (EPL) Scarlet mobs: silver and Runecloth (Classic).",
  } },
  { 60, 61, {
    "Dire Maul East: Satyrs for Felcloth and Demonic Runes, plus herbs inside (Skycoach).",
    "Quest XP turns into gold at 60, so finish leftover quests.",
    "Herbs: Black Lotus, Plaguebloom, Gromsblood; Black Lotus is crowded.",
    "Save 1,000g for Journeyman Riding (fast mount).",
  } },
}

R.GOLD_ALWAYS = {
  "Flip: buy well under the usual price and relist; Skycoach puts margins at 20-40%. Only flip items you've watched for days, and count the 5% cut.",
  "Sell in the evening and around raid nights; buy late at night or midweek when supply is high.",
  "Forever demand: sharpening stones, grenades for non-engineers, and Cooking buff food (XP bonus).",
}

-- Gold per profession you have
R.PROF_GOLD = {
  Skinning = "Sell leather at your level's spot above. Leather sells better than ore or herbs in Forever (MeinMMO).",
  Mining = "Sell bars and stone to leveling crafters; keep a Mining step ahead of the crowd (Mithril/Thorium).",
  Herbalism = "Alchemists buy every herb; Gromsblood (Felwood), Ghost Mushroom (Hinterlands), Dreamfoil (Azshara) at higher skill.",
  Fishing = "Sell fish that alchemists and cooks need (Oily Blackmouth, Firefin, Stonescale Eel); cook buff food for the XP bonus.",
  Alchemy = "Called the best gold profession in Forever (Skycoach): potions and elixirs always sell.",
  Enchanting = "Rare formulas and enchanting for tips; sell shards/dust from greens you'd vendor.",
  Engineering = "Grenades and dynamite sell to non-engineers in Forever.",
  Blacksmithing = "Sharpening stones and shield spikes matter more in Forever.",
  Tailoring = "Bags always sell. Pair with Enchanting to disenchant what you make.",
  Leatherworking = "Camp Tents (XP buff) and armor kits sell to levelers.",
  Cooking = "Well Fed food gives +5% kill XP in Forever, so levelers buy it.",
}

-- Gathering skill routes (Classic zones; mining from your notes)
R.GATHER = {
  Mining = {
    { 1, 105, "Smelt AH Copper Ore (1-65), Tin (65-75), Bronze (75-105) in town. Train Journeyman at 65." },
    { 105, 125, "Tin and Silver: Wetlands, Redridge. Thelgen Rock incendicite veins respawn fast." },
    { 125, 175, "Iron and Gold: Arathi, Stranglethorn, Riverglades. Train Expert at 125." },
    { 175, 245, "Mithril and Truesilver: Badlands, Hinterlands. Artisan at 200 (Ironforge)." },
    { 245, 300, "Thorium: Un'Goro, Plaguelands, Winterspring." },
  },
  Skinning = {
    { 1, 75, "Starting zones and Westfall/Loch Modan beasts." },
    { 75, 150, "Wetlands, Redridge, Hillsbrad (Medium Leather at 125+)." },
    { 150, 225, "Arathi, Stranglethorn, Swamp of Sorrows, Dustwallow (Heavy Leather)." },
    { 225, 300, "Feralas, Tanaris, Hinterlands, Un'Goro (Thick), then Plaguelands/Winterspring (Rugged). Artisan at 225." },
  },
  Herbalism = {
    { 1, 70, "Peacebloom, Silverleaf, Earthroot in starting zones." },
    { 70, 115, "Mageroyal, Briarthorn: Westfall, Redridge, Darkshore." },
    { 115, 170, "Bruiseweed, Wild Steelbloom, Kingsblood: Wetlands, Hillsbrad." },
    { 170, 230, "Liferoot, Fadeleaf, Goldthorn, Khadgar's Whisker: Arathi, Stranglethorn, Hinterlands." },
    { 230, 300, "Sungrass, Gromsblood, Dreamfoil, Mountain Silversage: Feralas, Felwood, Un'Goro, Winterspring." },
  },
  Fishing = {
    { 1, 75, "Any starting-zone water." },
    { 75, 150, "Westfall, Loch Modan, Wetlands. Buy Expert Fishing (Old Man Heming's book, Booty Bay) at 125." },
    { 150, 225, "Arathi, Stranglethorn, Desolace, Dustwallow." },
    { 225, 300, "Tanaris, Feralas, Azshara with a +Fishing pole or lure. Artisan from Nat Pagle (Dustwallow)." },
  },
}

---------------------------------------------------------------------------
-- Build the tab
---------------------------------------------------------------------------
local function ItemName(id)
  local n = GetItemInfo and GetItemInfo(id)
  if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return n or ("item " .. id)
end

-- The guide step you're on (and the next two) for a crafting profession.
local function CraftSteps(prof, skill)
  local sites = ns.Guides and ns.Guides[prof]
  if not sites then return nil end
  local prices = ns.Data.Prices("faction")
  local lines = {}
  local names = {}
  for site in pairs(sites) do names[#names + 1] = site end
  table.sort(names)
  for _, site in ipairs(names) do
    local shown = 0
    for _, st in ipairs(sites[site]) do
      local from, to, rec, crafts, mats = st[1], st[2], st[3], st[4], st[5]
      if to > skill and shown < 3 then
        local left = crafts
        if skill > from then left = math.ceil(crafts * (to - skill) / (to - from)) end
        local parts, cost, priced = {}, 0, true
        for id, per in pairs(mats) do
          local q = math.ceil(per * left)
          parts[#parts + 1] = q .. "x " .. ItemName(id)
          local p = prices[id] and prices[id].p
          if p then cost = cost + p * q else priced = false end
        end
        table.sort(parts)
        local line = ("%s%d-%d|r %s x%d: %s"):format(from <= skill and "|cff00ff00" or "|cffffffff",
          from, to, rec, left, table.concat(parts, ", "))
        if cost > 0 then
          line = line .. ("  |cff888888~%s at AH%s|r"):format(ns.Data.Money(cost), priced and "" or " (some unpriced)")
        end
        if shown == 0 then lines[#lines + 1] = "|cffaaaaaa" .. site .. ":|r" end
        lines[#lines + 1] = line
        shown = shown + 1
      end
    end
  end
  return lines
end

local function GatherStep(prof, skill)
  for _, st in ipairs(R.GATHER[prof] or {}) do
    if skill < st[2] then return ("|cff00ff00%d-%d|r %s"):format(st[1], st[2], st[3]) end
  end
  return nil
end

local function InRange(lvl, a, b) return lvl >= a and lvl < b end

-- Returns a list of { topic, q, a, keywords } entries for this character,
-- in the order they should show.
function R.Entries()
  local out = {}
  local function Add(topic, q, a, kw) out[#out + 1] = { topic = topic, q = q, a = a, keywords = kw or "" } end
  local lvl = Lvl()
  local class = Class()
  local profs = (ns.Data and ns.Data.Char().professions) or {}

  -- 1. Gold
  local goldT = ("Gold routes (level %d)"):format(lvl)
  for _, b in ipairs(R.GOLD) do
    if InRange(lvl, b[1], b[2]) or InRange(lvl + 5, b[1], b[2]) and lvl < b[1] then
      Add(goldT, ("Level %d-%d"):format(b[1], math.min(b[2], 60)), "- " .. table.concat(b[3], "\n- "), "gold farm money")
    end
  end
  local mine = {}
  for name in pairs(profs) do if R.PROF_GOLD[name] then mine[#mine + 1] = name end end
  table.sort(mine)
  if #mine > 0 then
    local t = {}
    for _, name in ipairs(mine) do t[#t + 1] = "- " .. name .. ": " .. R.PROF_GOLD[name] end
    Add(goldT, "With your professions", table.concat(t, "\n"), "gold profession")
  end
  Add(goldT, "Auction house", "- " .. table.concat(R.GOLD_ALWAYS, "\n- "), "gold ah flip sell")

  -- 2. Leveling
  if lvl < 60 then
    local levT = ("Leveling (level %d)"):format(lvl)
    local z = {}
    for _, b in ipairs(R.ZONES) do
      if InRange(lvl, b[1], b[2]) or InRange(lvl + 4, b[1], b[2]) then z[#z + 1] = ("%d-%d: %s"):format(b[1], math.min(b[2], 60), b[3]) end
    end
    Add(levT, "Zones", table.concat(z, "\n"), "zone quest where")
    local d = {}
    for _, x in ipairs(R.DUNGEONS) do
      if lvl >= x[1] - 2 and lvl <= x[2] then
        d[#d + 1] = ("%s (%d-%d, %s)%s"):format(x[3], x[1], x[2], x[4], x[5] and " |cff33ff99new|r" or "")
      end
    end
    if #d > 0 then Add(levT, "Dungeons for your level", table.concat(d, "\n"), "dungeon instance") end
    Add(levT, "XP tips", R.XP_TIPS, "xp rested buff")
  end

  local c = R.CLASSES[class]
  if c then
    local cn = (UnitClass("player")) or class
    local cT = ("%s leveling"):format(cn)
    Add(cT, "Spec", c.spec, "spec build")
    local tl = {}
    for _, t in ipairs(c.talents) do
      if lvl <= t[2] then tl[#tl + 1] = t[3] end
    end
    if #tl > 0 then Add(cT, "Talents", table.concat(tl, "\n"), "talent build order") end
    Add(cT, "Rotation", c.rotation, "rotation abilities")
    local q = {}
    for _, x in ipairs(c.quests) do
      if x[1] >= lvl - 10 then
        q[#q + 1] = ("%s%d|r %s"):format(x[1] <= lvl and "|cff00ff00" or "|cffffffff", x[1], x[2])
      end
    end
    if #q > 0 then Add(cT, "Class quests (green = you can do it now)", table.concat(q, "\n"), "class quest") end
    Add(cT, "Tips", c.tips .. "\n|cff888888" .. c.url .. "|r", "tips")
  end

  -- 3. Professions
  local names = {}
  for name in pairs(profs) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local p = profs[name]
    local skill = p.skill or 0
    local head = ("%s %d/%d"):format(name, skill, p.max or 0)
    local body
    if skill >= 300 then body = "Maxed."
    elseif ns.Guides and ns.Guides[name] then
      local lines = CraftSteps(name, skill)
      if name == "Mining" then table.insert(lines, 1, GatherStep(name, skill) or "") end
      body = table.concat(lines, "\n")
    elseif R.GATHER[name] then
      body = GatherStep(name, skill)
    end
    if name == "First Aid" and skill >= 225 and (p.max or 0) <= 225 then
      body = "225-300: Triage quest from Doctor Gustaf VanHowzen, Theramore (level 35) unlocks Artisan." .. (body and body ~= "" and ("\n" .. body) or "")
    end
    if body and body ~= "" then
      if p.max and skill >= p.max and p.max < 300 then
        body = "|cffff6060At your cap: train the next rank.|r\n" .. body
      end
      Add("Profession leveling", head, body, "profession skill " .. name:lower())
    end
  end

  return out
end

-- Item names load in the background; redraw the guide once they arrive.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function()
  if ev.pending or not ns.RefreshWindow then return end
  ev.pending = true
  C_Timer.After(0.5, function() ev.pending = nil; ns.RefreshWindow() end)
end)
