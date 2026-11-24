-- Core.lua
-- Answers questions about quests: best / most XP / most gold / most popular,
-- in this area, a named zone, or anywhere, for your level, faction and class.
local addonName, ns = ...

AskQuestDB = AskQuestDB or {}

local Q = ns.quests          -- [id] = {name, zone, lvl, req, xp, copper, faction, classMask, kind, pop, giver}
local NAME, ZONE, LVL, REQ, XP, GOLD, FAC, CLS, KIND, POP, GIVER = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local GMAP, GX, GY, ENDER, EMAP, EX, EY, TRAVEL = 12, 13, 14, 15, 16, 17, 18, 19
local KIND_TEXT = { [1] = "Elite", [2] = "Dungeon" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Norm(s)
  return (s or ""):lower():gsub("[^%a%d]", "")
end

local zoneByNorm = {}
for i, z in ipairs(ns.zones) do zoneByNorm[Norm(z)] = i end

-- Short names people type for zones.
local ALIASES = {
  stv = "Stranglethorn Vale", stranglethorn = "Stranglethorn Vale",
  wpl = "Western Plaguelands", epl = "Eastern Plaguelands",
  ungoro = "Un'Goro Crater", hinterlands = "The Hinterlands", barrens = "The Barrens",
  ["1k"] = "Thousand Needles", needles = "Thousand Needles", hillsbrad = "Hillsbrad Foothills",
  arathi = "Arathi Highlands", alterac = "Alterac Mountains", redridge = "Redridge Mountains",
  stonetalon = "Stonetalon Mountains", dustwallow = "Dustwallow Marsh", swamp = "Swamp of Sorrows",
  sos = "Swamp of Sorrows", searing = "Searing Gorge", steppes = "Burning Steppes", blasted = "Blasted Lands",
  sw = "Stormwind City", stormwind = "Stormwind City", ironforge = "Ironforge", elwynn = "Elwynn Forest",
  dm = "The Deadmines", deadmines = "The Deadmines", vc = "The Deadmines", wc = "Wailing Caverns",
  bfd = "Blackfathom Deeps", stocks = "The Stockade", stockade = "The Stockade", gnomer = "Gnomeregan",
  rfk = "Razorfen Kraul", rfd = "Razorfen Downs", sm = "Scarlet Monastery", ulda = "Uldaman",
  zf = "Zul'Farrak", mara = "Maraudon", st = "The Temple of Atal'Hakkar", sunken = "The Temple of Atal'Hakkar",
  brd = "Blackrock Depths", brs = "Blackrock Spire", lbrs = "Blackrock Spire", ubrs = "Blackrock Spire",
  strat = "Stratholme", scholo = "Scholomance", sfk = "Shadowfang Keep", excavation = "Excavation Site: Wetlands",
  hyjal = "Mount Hyjal", zephras = "Zephras Isle",
}
ns.ZoneAliases = ALIASES

local function Commas(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local k
    s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end

function ns.Money(c)
  if not c or c < 0 then return "|cff888888? gold|r" end
  if c == 0 then return "|cff888888no gold|r" end
  local g, s, cc = floor(c / 10000), floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = "|cffffd700" .. g .. "g|r" end
  if s > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
  if cc > 0 and g == 0 then out[#out + 1] = "|cffeda55f" .. cc .. "c|r" end
  return table.concat(out, " ")
end

-- Gold: Blizzard API data first, then what you saw in game, then the database.
local function Gold(id, q)
  local api = ns.blizzGold and ns.blizzGold[id]
  if api then return api end
  local seen = AskQuestDB.gold and AskQuestDB.gold[id]
  if seen then return seen end
  return q[GOLD]
end
ns.Gold = Gold

-- Quests you turned in on this character, saved by AskQuest as a backup to the game's list.
-- Keyed by the character's GUID (always known); older saves keyed "Name-Realm" are merged in,
-- including ones saved as "Name-" when the realm name wasn't ready yet.
local doneList
local function DoneList()
  if doneList then return doneList end
  AskQuestDB.done = AskQuestDB.done or {}
  local guid = UnitGUID and UnitGUID("player")
  local name = UnitName and UnitName("player")
  if not guid then
    -- too early to know who we are; don't cache, don't save under a wrong key
    return AskQuestDB.done[(name or "?") .. "-"] or {}
  end
  local list = AskQuestDB.done[guid] or {}
  if name then
    for key, old in pairs(AskQuestDB.done) do
      if type(key) == "string" and type(old) == "table" and key:sub(1, #name + 1) == name .. "-" then
        for id, v in pairs(old) do if v then list[id] = true end end
        AskQuestDB.done[key] = nil
      end
    end
  end
  AskQuestDB.done[guid] = list
  doneList = list
  return list
end
ns.DoneList = DoneList

-- The game's own full list of quests this character has turned in, read once at login
-- (C_QuestLog.GetAllCompletedQuestIDs / GetQuestsCompleted) and kept up to date on turn-in.
local gameDone = {}
local function LoadGameDone()
  local ok, list
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(list) == "table" then
      for _, id in ipairs(list) do gameDone[id] = true end
    end
  elseif GetQuestsCompleted then
    ok, list = pcall(GetQuestsCompleted)
    if ok and type(list) == "table" then
      for id, v in pairs(list) do if v then gameDone[id] = true end end
    end
  end
end
ns.LoadGameDone = LoadGameDone

local function Flagged(id)
  if gameDone[id] or DoneList()[id] then return true end
  local ok, done
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
  elseif IsQuestFlaggedCompleted then ok, done = pcall(IsQuestFlaggedCompleted, id) end
  if ok and done then gameDone[id] = true return true end
  return false
end

-- Quests in your log right now, refreshed when the log changes.
local inLog, inLogStale = {}, true
local function LogSet()
  if not inLogStale then return inLog end
  inLogStale = false
  wipe(inLog)
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID then inLog[info.questID] = true end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, GetNumQuestLogEntries() do
      local _, _, _, isHeader, _, _, _, qid = GetQuestLogTitle(i)
      if not isHeader and qid then inLog[qid] = true end
    end
  end
  return inLog
end

-- Done = the game says so, you turned it in, or you've done (or picked up) a later step of its chain.
local function IsDone(id)
  if Flagged(id) then return true end
  local log = LogSet()
  local nxt, seen = ns.chainNext and ns.chainNext[id], 0
  while nxt and seen < 40 do
    if Flagged(nxt) or log[nxt] then return true end
    nxt, seen = ns.chainNext[nxt], seen + 1
  end
  return false
end

-- Questie (installed) knows which quests close off others: "pick one of these" quests,
-- breadcrumbs that lead to a quest you've already done or picked up, and quests that
-- stop being offered once another is turned in. Use its database when it's loaded.
local questieDB
local function QuestieField(id, field)
  if not questieDB then
    if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
    local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
    if not (ok and type(m) == "table") then return nil end
    if type(m.QueryQuestSingle) ~= "function" then return nil end -- not ready yet, try later
    questieDB = m
  end
  local ok, v = pcall(questieDB.QueryQuestSingle, id, field)
  if ok then return v end
end

ns.QuestieField = QuestieField
function ns.HasQuestie()
  if not questieDB then QuestieField(7, "name") end -- loads it if Questie is ready
  return questieDB ~= nil
end

local function DoneOrInLog(id) return id and id ~= 0 and (Flagged(id) or LogSet()[id]) end

-- Can't be done any more, though the game doesn't flag it as completed.
local function ClosedOff(id)
  local ex = QuestieField(id, "exclusiveTo")
  if type(ex) == "table" then
    for _, x in pairs(ex) do if DoneOrInLog(x) then return true end end
  end
  local target = QuestieField(id, "breadcrumbForQuestId")
  if DoneOrInLog(target) then return true end
  local nxt = QuestieField(id, "nextQuestInChain")
  if DoneOrInLog(nxt) then return true end
  local untilDone = QuestieField(id, "availableUntilCompleted")
  if untilDone and untilDone ~= 0 and Flagged(untilDone) then return true end
  return false
end

-- Hidden from suggestions: done, or no longer possible because of something you did.
local function IsGone(id)
  return IsDone(id) or ClosedOff(id)
end
ns.IsGone = IsGone

local function PlayerInfo()
  local level = UnitLevel("player") or 1
  local fac = (UnitFactionGroup("player") == "Horde") and 2 or 1
  local _, _, classID = UnitClass("player")
  local classMask = classID and (2 ^ (classID - 1)) or 0
  return level, fac, classMask
end

function ns.CurrentZone()
  local names = { GetRealZoneText and GetRealZoneText(), GetZoneText and GetZoneText() }
  if C_Map and C_Map.GetBestMapForUnit then
    local id = C_Map.GetBestMapForUnit("player")
    local info = id and C_Map.GetMapInfo(id)
    if info then
      names[#names + 1] = info.name
      local parent = info.parentMapID and C_Map.GetMapInfo(info.parentMapID)
      if parent then names[#names + 1] = parent.name end
    end
  end
  for _, n in ipairs(names) do
    local i = n and zoneByNorm[Norm(n)]
    if i then return i, ns.zones[i] end
  end
  return nil, names[1]
end

---------------------------------------------------------------------------
-- Understanding the question
---------------------------------------------------------------------------
local function Has(text, words)
  for _, w in ipairs(words) do
    if text:find(w) then return true end
  end
  return false
end

local function FindZone(text)
  local best, bestLen
  local squashed = Norm(text)
  for norm, i in pairs(zoneByNorm) do
    if #norm >= 4 and squashed:find(norm, 1, true) and (not bestLen or #norm > bestLen) then
      best, bestLen = i, #norm
    end
  end
  if best then return best end
  for word in text:gmatch("[%w']+") do
    local z = ALIASES[word:gsub("'", "")]
    if z and zoneByNorm[Norm(z)] then return zoneByNorm[Norm(z)] end
  end
end

-- Returns a filter/sort spec from a plain-English question.
function ns.Parse(text)
  text = " " .. (text or ""):lower() .. " "
  local spec = { sort = "best", limit = 10 }

  if Has(text, { "gold", "money", "silver", "copper", "pays", " cash" }) then spec.sort = "gold"
  elseif Has(text, { "xp", " exp", "experience", "level up", "leveling", "levelling" }) then spec.sort = "xp"
  elseif Has(text, { "popular", "common", "everyone", "most people", "most done", "usual" }) then spec.sort = "pop"
  end

  if Has(text, { " here ", "this area", "this zone", "around here", "nearby", "current zone", " near " }) then
    spec.zone = ns.CurrentZone()
    spec.here = true
    if not spec.zone then spec.unknownZone = select(2, ns.CurrentZone()) end
  else
    spec.zone = FindZone(text)
  end
  spec.anywhere = Has(text, { "anywhere", "all zones", "everywhere", "any zone" })

  local a, b = text:match("(%d+)%s*%-%s*(%d+)")
  local one = text:match("level%s*(%d+)") or text:match("lvl%s*(%d+)") or text:match(" l(%d+) ")
  if a and b then spec.minL, spec.maxL = tonumber(a), tonumber(b)
  elseif one then spec.minL, spec.maxL = tonumber(one) - 2, tonumber(one) + 3 end
  spec.forMe = Has(text, { "for me", "my level", " i can ", "can i " })
  spec.allLevels = Has(text, { "any level", "all levels" })

  if Has(text, { "dungeon", "instance" }) then spec.kind = 2
  elseif Has(text, { "solo", "alone", "no group", "by myself" }) then spec.kind = 0
  elseif Has(text, { "elite", "group quest" }) then spec.kind = 1 end

  spec.newOnly = Has(text, { "new quest", "forever quest", "new in forever", "forever only" })
  spec.showDone = Has(text, { "completed", "already done", "including done", "finished" })
  local n = text:match("top%s*(%d+)") or text:match("(%d+)%s*quests")
  if n then spec.limit = math.min(tonumber(n), 50) end
  if Has(text, { " list ", " all ", "every" }) then spec.limit = 40 end

  -- No keywords at all: treat it as a quest name search.
  local keyword = spec.sort ~= "best" or spec.zone or spec.here or spec.kind or spec.minL or spec.newOnly
    or Has(text, { "best", "good", "top", "which", "what", "quest" })
  if not keyword then spec.name = strtrim(text) end
  return spec
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
function ns.Search(spec)
  local level, fac, classMask = PlayerInfo()
  local minL, maxL = spec.minL, spec.maxL
  if not minL and not spec.name and not spec.allLevels and (spec.forMe or spec.here or not spec.zone) then
    minL, maxL = level - 3, level + 4
  end
  local results, hiddenDone = {}, 0
  for id, q in pairs(Q) do
    local ok = (q[FAC] == 0 or q[FAC] == fac)
      and (q[CLS] == 0 or bit.band(q[CLS], classMask) ~= 0)
      and (not spec.zone or spec.anywhere or q[ZONE] == spec.zone)
      and (not minL or (q[LVL] >= minL and q[LVL] <= maxL))
      and (spec.kind == nil or q[KIND] == spec.kind
           or (spec.kind == 2 and ns.DungeonLead and ns.DungeonLead(id) ~= nil))
      and (not spec.newOnly or ns.IsNew(id))
      and (not spec.name or q[NAME]:lower():find(spec.name, 1, true))
    if ok and not spec.showDone and not spec.name and IsGone(id) then
      ok, hiddenDone = false, hiddenDone + 1
    end
    if ok then results[#results + 1] = id end
  end

  -- "Best" mixes XP (55%), gold (25%) and popularity (20%), scaled to the results.
  -- gold counts what the item rewards sell for too (AH or vendor, see Reward.lua)
  local Gold = function(id, q) return ns.TotalGold and ns.TotalGold(id, q) or Gold(id, q) end
  local maxXP, maxGold = 1, 1
  for _, id in ipairs(results) do
    maxXP = math.max(maxXP, Q[id][XP])
    maxGold = math.max(maxGold, Gold(id, Q[id]))
  end
  local function Score(id)
    local q = Q[id]
    if spec.sort == "xp" then return q[XP] + Gold(id, q) / 1e6 end
    if spec.sort == "gold" then return Gold(id, q) + q[XP] / 1e6 end
    if spec.sort == "pop" then return q[POP] + q[XP] / 1e6 end
    local s = 0.55 * q[XP] / maxXP + 0.25 * math.max(Gold(id, q), 0) / maxGold + 0.20 * q[POP] / 100
    -- Chains that lead into a dungeon quest are important: rank them up.
    if ns.DungeonImportant and ns.DungeonImportant(id, level) then s = s + 0.35 end
    return s
  end
  -- "Best for me": rank by what each quest is worth to you right now
  -- (XP for your level, gold, upgrades for your spec, effort), see Reward.lua.
  local personal = spec.sort == "best" and spec.forMe and ns.Assess
  local scores = {}
  for _, id in ipairs(results) do
    scores[id] = personal and ns.Assess(id).score or Score(id)
  end
  table.sort(results, function(x, y) return scores[x] > scores[y] end)
  return results, { minL = minL, maxL = maxL, level = level, hiddenDone = hiddenDone }
end

function ns.Line(i, id)
  local q = Q[id]
  local tags = {}
  if KIND_TEXT[q[KIND]] then tags[#tags + 1] = KIND_TEXT[q[KIND]] end
  if ns.IsNew(id) then tags[#tags + 1] = "New" end
  local lead = ns.DungeonImportant and ns.DungeonImportant(id)
  if lead then tags[#tags + 1] = "|cffa335eeImportant: leads to " .. ns.DungeonWhere(lead) .. "|cffff8040" end
  if IsDone(id) then tags[#tags + 1] = "Done" end
  local tag = #tags > 0 and (" |cffff8040[" .. table.concat(tags, ", ") .. "]|r") or ""
  local level = UnitLevel("player") or 1
  local lvlColor = (q[REQ] > level) and "|cffff4040" or "|cffffffff"
  local giver = q[GIVER] > 0 and (" from " .. ns.givers[q[GIVER]]) or ""
  return ("%d. |cffffd200%s|r %s[%d]|r%s  %s XP, %s, pop %d  |cff888888%s%s|r"):format(
    i, q[NAME], lvlColor, q[LVL], tag, Commas(q[XP]), ns.Money(Gold(id, q)), q[POP], ns.zones[q[ZONE]], giver)
end

ns.Commas = Commas
ns.F = { NAME = NAME, ZONE = ZONE, LVL = LVL, REQ = REQ, XP = XP, GOLD = GOLD, FAC = FAC, CLS = CLS, KIND = KIND, POP = POP, GIVER = GIVER,
  GMAP = GMAP, GX = GX, GY = GY, ENDER = ENDER, EMAP = EMAP, EX = EX, EY = EY, TRAVEL = TRAVEL }
ns.IsDone = IsDone

-- Is this quest in your quest log right now?
function ns.InLog(id)
  if not id then return false end
  if C_QuestLog and C_QuestLog.IsOnQuest and id then
    local ok, on = pcall(C_QuestLog.IsOnQuest, id)
    if ok then return on end
  end
  if not (GetNumQuestLogEntries and GetQuestLogTitle) then return false end
  for i = 1, GetNumQuestLogEntries() do
    local _, _, _, isHeader, _, _, _, qid = GetQuestLogTitle(i)
    if not isHeader and qid == id then return true end
  end
  return false
end
ns.PlayerInfo = PlayerInfo
ns.KIND_TEXT = KIND_TEXT

local SORT_TEXT = { best = "Best", xp = "Most XP", gold = "Most gold", pop = "Most popular" }

function ns.Answer(text)
  local spec = ns.Parse(text)
  local results, info = ns.Search(spec)
  local where = spec.name and ('name contains "' .. spec.name .. '"')
    or (spec.zone and not spec.anywhere and ns.zones[spec.zone])
    or (spec.unknownZone and (spec.unknownZone .. " (no quest data for this zone, showing all zones)"))
    or "all zones"
  local lv = info.minL and (" | levels " .. math.max(1, info.minL) .. "-" .. info.maxL) or ""
  local hidden = (info.hiddenDone or 0) > 0 and (", %d you've done are hidden"):format(info.hiddenDone) or ""
  local title = (spec.forMe and spec.sort == "best") and "Best quests for you, most valuable first" or (SORT_TEXT[spec.sort] .. " quests")
  local header = ("|cff33ccff%s: %s%s|r  (%d found%s)"):format(title, where, lv, #results, hidden)
  local lines = { header }
  for i = 1, math.min(#results, spec.limit) do
    lines[#lines + 1] = ns.Line(i, results[i])
    if spec.forMe and ns.WhyShort then
      local why, a = ns.WhyShort(results[i])
      lines[#lines + 1] = ("    %s (value %.1f) |cff33ff33why:|r %s"):format(a.tier, a.score, why)
    end
  end
  if #results == 0 then
    lines[#lines + 1] = "Nothing matches. Try 'anywhere', 'any level', or another zone."
  end
  return lines, results, spec, header
end

---------------------------------------------------------------------------
-- Quest dialog info + learning real gold
---------------------------------------------------------------------------
local function Rank(id)
  local q = Q[id]
  if not q then return end
  local _, fac, classMask = PlayerInfo()
  local better, total = 0, 0
  for oid, o in pairs(Q) do
    if o[ZONE] == q[ZONE] and math.abs(o[LVL] - q[LVL]) <= 4 and (o[FAC] == 0 or o[FAC] == fac)
      and (o[CLS] == 0 or bit.band(o[CLS], classMask) ~= 0) then
      total = total + 1
      if o[XP] > q[XP] then better = better + 1 end
    end
  end
  return better + 1, total
end

local function OnQuestShown(event)
  local id = GetQuestID and GetQuestID()
  if not id or id == 0 then return end
  local money = GetRewardMoney and GetRewardMoney()
  if money and (event == "QUEST_DETAIL" or event == "QUEST_COMPLETE") then
    AskQuestDB.gold = AskQuestDB.gold or {}
    AskQuestDB.gold[id] = money
  end
end
ns.Rank = Rank

local function Refresh()
  if ns.RefreshWindow then pcall(ns.RefreshWindow) end
end
local function RefreshSoon(delay)
  if C_Timer and C_Timer.After then C_Timer.After(delay, Refresh) else Refresh() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    doneList = nil
    LoadGameDone()
    DoneList()
    inLogStale = true
    return
  end
  if event == "QUEST_TURNED_IN" then
    local questID = a1
    if questID then
      DoneList()[questID] = true
      gameDone[questID] = true
    end
    inLogStale = true
    -- Refresh straight away, and again once the log and the game's list have caught up.
    Refresh()
    RefreshSoon(1)
    return
  end
  if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
    inLogStale = true
    RefreshSoon(0.5)
    return
  end
  if event == "QUEST_LOG_UPDATE" then
    inLogStale = true
    return
  end
  OnQuestShown(event)
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local HELP = {
  { "Ask in plain words", {
    { "best quest here", "best quests in this zone for you" },
    { "most xp for me", "or: most gold in Wetlands, most popular quests in Duskwood" },
    { "best dungeon quests level 30-35", "or: solo xp quests anywhere" },
    { "<quest name>", "look up one quest" },
  } },
  { "Windows and settings", {
    { "(nothing)", "open the quest chart (or click the minimap button)" },
    { "options", "open the AskQuest settings page" },
    { "info on|off", "reward and worth-it panel at quest givers and in the quest log" },
    { "minimap on|off", "the minimap button" },
    { "go", "box to type coordinates (45 62 or Duskwood 45 62); Enter opens the map there and pings it" },
    { "45 62", "or: go stv 30 40 - straight to a spot; go clear removes the waypoint" },
    { "tracker on|off", "[x, y] of the nearest mob/object in front of each objective in Questie's tracker; click it to ping the map" },
    { "docks", "boats, zeppelins and trams in this zone and where they go (markers on the world map)" },
    { "dock here", "or: dock add <text>, docks on|off, docks banner off - fix or add a dock marker" },
    { "guide", "where the Prot leveling guide sends you now (\"best for me\" follows it)" },
    { "guide on|off", "let \"best for me\" follow the leveling guide" },
  } },
}

local function ShowHelp()
  ns.Print("ask about quests (type /aq then your question). Switches are also in Esc > Options > AddOns > AskQuest.")
  for _, group in ipairs(HELP) do
    print("  |cff33ccff" .. group[1] .. "|r")
    for _, c in ipairs(group[2]) do
      print(("     |cffffd200%s|r  %s"):format(c[1], c[2]))
    end
  end
end

SLASH_ASKQUEST1, SLASH_ASKQUEST2 = "/aq", "/askquest"
SlashCmdList.ASKQUEST = function(msg)
  msg = strtrim(msg or "")
  local lower = msg:lower()
  if msg == "" then return ns.ToggleWindow() end
  if lower == "help" then ShowHelp() return end
  if lower == "options" or lower == "settings" or lower == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
    return
  end
  if lower == "guide" then
    ns.Print(ns.Guide and ns.Guide.Describe(UnitLevel("player") or 1) or "guide not loaded.")
    if AskQuestDB.noGuide then ns.Print("guide is off for \"best for me\" (/aq guide on).") end
    return
  end
  if lower == "guide off" then AskQuestDB.noGuide = true ns.Print("\"best for me\" no longer follows the leveling guide.") return end
  if lower == "guide on" then AskQuestDB.noGuide = nil ns.Print("\"best for me\" follows the Prot leveling guide.") return end
  if lower == "info off" then AskQuestDB.info = false ns.Print("reward panel off.") return end
  if lower == "info on" then AskQuestDB.info = true ns.Print("reward panel on.") return end
  if lower == "minimap off" or lower == "minimap on" then
    AskQuestDB.minimap = AskQuestDB.minimap or {}
    AskQuestDB.minimap.hide = (lower == "minimap off")
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    ns.Print("minimap button " .. (lower == "minimap off" and "hidden. /aq minimap on brings it back." or "shown."))
    return
  end
  if lower == "tracker off" or lower == "tracker on" then
    local on = (lower == "tracker on")
    if ns.SetTrackerCoords then ns.SetTrackerCoords(on) else AskQuestDB.trackerCoords = on end
    ns.Print("tracker coordinates " .. (on and "on." or "off. /aq tracker on brings them back."))
    if on and ns.TrackerCoordsAvailable and not ns.TrackerCoordsAvailable() then ns.Print("(needs Questie's quest tracker.)") end
    return
  end
  if (lower == "docks" or lower == "dock" or lower:match("^docks?%s")) and ns.DockCommand then
    ns.DockCommand(lower:gsub("^docks?%s*", ""), msg)
    return
  end
  if lower == "go" or lower == "coords" or lower == "way" then
    if ns.ToggleCoordsBox then ns.ToggleCoordsBox() end
    return
  end
  if lower == "go clear" or lower == "way clear" or lower == "coords clear" then
    if ns.ClearCoords then ns.ClearCoords() ns.Print("waypoint cleared.") end
    return
  end
  -- "/aq 45 62", "/aq go duskwood 45 62", "/aq way stv 30 40"
  do
    local rest = lower:match("^go%s+(.+)$") or lower:match("^way%s+(.+)$") or lower:match("^coords%s+(.+)$")
    if not rest and msg:match("^%s*%d+%.?%d*[%s,]+%d+%.?%d*%s*$") then rest = msg end
    if rest and ns.GoToCoords then
      ns.ShowCoordsBox(false)
      if ns.GoToCoords(rest) and AskQuestCoordsEdit then AskQuestCoordsEdit:SetText(rest) end
      return
    end
  end
  local lines = ns.Answer(msg)
  for i = 1, math.min(#lines, 11) do print(lines[i]) end
  if #lines > 11 then print("   |cff888888" .. (#lines - 11) .. " more in the quest chart window.|r") end
  ns.ShowInWindow(msg)
end
