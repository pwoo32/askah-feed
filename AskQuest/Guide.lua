-- Guide.lua
-- "Best for me" follows a WoW Forever leveling guide for a Protection Warrior.
-- Route: wowforeverinfo.com Alliance 1-60 guide (the most complete Forever route,
-- updated 9 Nov 2026), cross-checked with warcraftmaps.com (patch 1.60.1) and
-- foreverdb.net. Dungeon picks and skips for a tank: conquestcapped.com Forever
-- warrior leveling + leveling guides (Nov 2026). Prot levels by tanking dungeons
-- (tanks are scarce in the group finder), so on-route dungeon quests cost much
-- less effort for you than for a dps.
-- Horde: no Forever Horde route is loaded yet, so nothing changes for Horde.
local _, ns = ...
local G = {}
ns.Guide = G

-- { fromLevel, toLevel, zones, dungeons }
local ALLIANCE = {
  { 1, 12, { "Elwynn Forest", "Dun Morogh", "Teldrassil", "Zephras Isle" }, {} },
  { 10, 20, { "Westfall", "Loch Modan", "Darkshore" }, { "The Deadmines" } },
  { 15, 25, { "Redridge Mountains" }, { "The Deadmines" } },
  { 20, 30, { "Duskwood", "Wetlands", "Ashenvale" },
            { "The Stockade", "Blackfathom Deeps", "Excavation Site: Wetlands" } },
  { 27, 32, { "Hillsbrad Foothills" }, { "Dalaran" } },
  { 28, 40, { "Arathi Highlands", "Alterac Mountains", "Stranglethorn Vale", "Desolace" },
            { "Dalaran", "Gnomeregan", "Scarlet Monastery" } },
  { 35, 45, { "Riverglades", "Dustwallow Marsh", "Badlands", "Swamp of Sorrows" },
            { "Scarlet Monastery", "Uldaman" } },
  { 40, 50, { "Feralas", "Tanaris", "The Hinterlands", "Searing Gorge", "Shen'dralas" },
            { "Uldaman", "Zul'Farrak", "Maraudon", "Alcaz Island" } },
  { 48, 55, { "Un'Goro Crater", "Felwood", "Azshara", "Blasted Lands" },
            { "Maraudon", "The Temple of Atal'Hakkar" } },
  { 51, 60, { "Western Plaguelands", "Eastern Plaguelands", "Burning Steppes", "Winterspring", "Silithus" },
            { "The Temple of Atal'Hakkar", "Blackrock Depths", "Blackrock Spire", "Dire Maul", "Scholomance", "Stratholme" } },
  { 58, 60, { "Mount Hyjal" }, {} },
}

-- Guides say these aren't worth it for Alliance (few quests, long walks).
local SKIP = {
  ["Shadowfang Keep"] = "guides say skip it for Alliance (almost no Alliance quests)",
  ["Razorfen Kraul"] = "guides say skip it for Alliance (two quests)",
  ["Razorfen Downs"] = "guides say skip it for Alliance (weak quests)",
}

local zoneIndex
local function Z(name)
  if not zoneIndex then
    zoneIndex = {}
    for i, z in ipairs(ns.zones or {}) do zoneIndex[z] = i end
  end
  return zoneIndex[name]
end

-- Which zones and dungeons the guide sends you to at this level.
function G.Plan(level)
  if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then return nil end
  local zones, dungeons, names = {}, {}, {}
  for _, b in ipairs(ALLIANCE) do
    if level >= b[1] - 1 and level <= b[2] + 1 then
      for _, n in ipairs(b[3]) do local i = Z(n); if i and not zones[i] then zones[i] = true; names[#names + 1] = n end end
      for _, n in ipairs(b[4]) do local i = Z(n); if i then dungeons[i] = true end end
    end
  end
  return { zones = zones, dungeons = dungeons, names = names }
end

local function IsProt()
  local s = ns.Spec and ns.Spec()
  return s == "PROT"
end

-- Called from ns.Assess. Returns the new effort and a score multiplier.
function G.Adjust(q, level, effort, why)
  if not q or (AskQuestDB and AskQuestDB.noGuide) then return effort, 1 end
  local plan = G.Plan(level)
  if not plan then return effort, 1 end
  local F = ns.F
  local zone, kind = q[F.ZONE], q[F.KIND] or 0
  local zname = ns.zones[zone]
  if kind == 2 then
    if SKIP[zname] then
      why[#why + 1] = SKIP[zname]
      return effort * 1.2, 1
    end
    if plan.dungeons[zone] then
      if IsProt() then
        -- 2.5x -> about 1.3x: as the tank you get groups fast.
        effort = effort / 1.9
        why[#why + 1] = "on the guide's dungeon list, and you tank (groups form fast)"
      else
        why[#why + 1] = "on the guide's dungeon list"
      end
      return effort, 1.15
    end
    return effort, 1
  end
  if plan.zones[zone] then
    why[#why + 1] = "on the leveling guide route"
    return effort, 1.25
  end
  why[#why + 1] = "off the guide route"
  return effort * 1.1, 1
end

-- One line for /aq guide.
function G.Describe(level)
  local plan = G.Plan(level)
  if not plan then return "No Forever Horde leveling route is loaded yet." end
  local d = {}
  for i in pairs(plan.dungeons) do d[#d + 1] = ns.zones[i] end
  table.sort(d)
  return ("Guide route at %d: %s. Dungeons: %s."):format(level, table.concat(plan.names, ", "),
    #d > 0 and table.concat(d, ", ") or "none yet")
end
