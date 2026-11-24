-- TrackerCoords.lua
-- Questie's quest tracker: puts the coordinates of the nearest spot for each
-- objective in front of it, like "[49, 36] Kobold Vermin slain: 3/10".
-- "Nearest" means the closest mob, object or drop source (from Questie's own
-- spawn data) to where you stand now; it updates as you move.
-- Click the [x, y] tag to open the world map there with AskQuest's ping and
-- star marker (plus the game's map pin, TomTom if installed, and the arrow box).
-- Clicking the rest of the line still does what Questie does (open quest log,
-- right-click menu, ...). /aq tracker off|on turns it off/on.
local _, ns = ...

local LB, TLP, TL, DU, ZDB, QT -- Questie modules
local decorated = setmetatable({}, { __mode = "k" }) -- lines we touched
local measure -- hidden font string for the tag width
local COLOR = "|cff66ccff"

local function Enabled() return AskQuestDB and AskQuestDB.trackerCoords ~= false end

local function Import(name)
  local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
  return ok and m or nil
end

-- Nearest spawn for one objective: map ID, x, y (0-100), name, distance in yards (nil if far/other continent)
local function Nearest(objective)
  if not objective or objective.Completed then return end
  local list = objective.spawnList
  if (not list or not next(list)) and objective.enrichment then list = objective.enrichment.spawnList end
  if not list or not next(list) then return end
  local ok, spawn, zone, name, dist = pcall(DU.GetNearestObjective, list)
  if not ok or not spawn or not zone or not spawn[1] or spawn[1] < 0 then return end
  local okMap, map = pcall(ZDB.GetUiMapIdByAreaId, ZDB, zone)
  if not okMap or not map then return end
  return map, spawn[1], spawn[2], name, (dist and dist < 500000) and dist or nil
end

local function Tag(x, y) return ("[%d, %d] "):format(math.floor(x + 0.5), math.floor(y + 0.5)) end

local function Undecorate(line)
  if line.aqBtn then line.aqBtn:Hide() end
  if line.aqPrefix and line.label then
    local text = line.label:GetText() or ""
    if text:sub(1, #line.aqPrefix) == line.aqPrefix then line.label:SetText(text:sub(#line.aqPrefix + 1)) end
  end
  line.aqPrefix, line.aqCoord = nil, nil
  decorated[line] = nil
end

local function ZoneName(map)
  local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or "?"
end

local function OnClick(btn)
  local c = btn.line and btn.line.aqCoord
  if not c then return end
  if ns.GoToPoint then ns.GoToPoint(c.map, c.x, c.y, c.name) end
end

local function OnEnter(btn)
  local c = btn.line and btn.line.aqCoord
  if not c then return end
  GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
  GameTooltip:AddLine(c.name or "Objective", 1, 1, 1)
  GameTooltip:AddLine(("%s %.1f, %.1f"):format(ZoneName(c.map), c.x, c.y), 1, 0.82, 0)
  if c.dist then
    GameTooltip:AddLine(("Nearest spot, about %s yards away"):format(ns.Commas and ns.Commas(math.floor(c.dist + 0.5)) or math.floor(c.dist + 0.5)), 0.8, 0.8, 0.8)
  else
    GameTooltip:AddLine("Nearest spot (not in your zone)", 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Click: ping it on the world map and pin it", 0.4, 0.8, 1)
  GameTooltip:Show()
end

local function Button(line)
  if line.aqBtn then return line.aqBtn end
  local b = CreateFrame("Button", nil, line)
  b.line = line
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", OnClick)
  b:SetScript("OnEnter", OnEnter)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.4, 0.8, 1, 0.18)
  line.aqBtn = b
  return b
end

-- Size and place the clickable box over the [x, y] tag at the start of the label.
local function Place(line)
  local b, c = line.aqBtn, line.aqCoord
  if not b or not c or not line.aqPrefix then return end
  if not measure then
    measure = UIParent:CreateFontString(nil, "BACKGROUND")
    measure:Hide()
  end
  local font, size, flags = line.label:GetFont()
  if font then measure:SetFont(font, size, flags) end
  measure:SetText(line.aqPrefix)
  local w = (measure.GetUnboundedStringWidth and measure:GetUnboundedStringWidth()) or measure:GetStringWidth() or 40
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", line.label, "TOPLEFT", -2, 1)
  b:SetSize(w + 2, (size or 12) + 2)
  b:SetFrameLevel(line:GetFrameLevel() + 5)
  b:Show()
end

local function SetCoord(line, map, x, y, name, dist)
  line.aqCoord = { map = map, x = x, y = y, name = name, dist = dist }
  local tag = COLOR .. Tag(x, y) .. "|r"
  local text = line.label:GetText() or ""
  if line.aqPrefix and text:sub(1, #line.aqPrefix) == line.aqPrefix then text = text:sub(#line.aqPrefix + 1) end
  line.aqPrefix = tag
  line.label:SetText(tag .. text)
  decorated[line] = true
end

-- After Questie builds an objective line
local function AfterAddObjective(options)
  local line = TLP.GetCurrentLine()
  if not line or not line.label then return end
  if line.aqBtn then line.aqBtn:Hide() end
  line.aqPrefix, line.aqCoord = nil, nil
  if not Enabled() or not options or not options.objective or line.Objective ~= options.objective then return end
  local map, x, y, name, dist = Nearest(options.objective)
  if not map then return end
  SetCoord(line, map, x, y, name, dist)
  Button(line)
  -- let Questie size the line for the longer text
  local marginLeft = options.marginLeft or (TL.GetMargins and TL.GetMargins().objective) or 0
  pcall(TL.UpdateLineWidth, line, marginLeft)
  line:SetHeight(line.label:GetHeight() + 1)
  Place(line)
end

-- Questie only re-wrote the text (progress changed, maybe in combat): put the tag back.
local function AfterUpdateQuestLines(questId)
  for line in pairs(decorated) do
    if line.Quest and line.Quest.Id == questId and line.Objective then
      local map, x, y, name, dist = Nearest(line.Objective)
      local text = line.label:GetText() or ""
      if map then
        if line.aqPrefix and text:sub(1, #line.aqPrefix) == line.aqPrefix then text = text:sub(#line.aqPrefix + 1) end
        line.aqPrefix = nil
        line.label:SetText(text)
        SetCoord(line, map, x, y, name, dist)
        Place(line)
      else
        Undecorate(line)
      end
    end
  end
end

local function AfterReset()
  for line in pairs(decorated) do
    if line.aqBtn then line.aqBtn:Hide() end
    line.aqPrefix, line.aqCoord = nil, nil
    decorated[line] = nil
  end
end

local function AfterUpdate()
  for line in pairs(decorated) do
    if line.mode ~= "objective" or not line:IsShown() then
      if line.aqBtn then line.aqBtn:Hide() end
    else
      Place(line)
    end
  end
end

-- As you move, the nearest spot changes: check every few seconds.
local function Tick()
  if not Enabled() then return end
  local changed = false
  for line in pairs(decorated) do
    local c = line.aqCoord
    if c and line.Objective and line:IsShown() then
      local map, x, y, name, dist = Nearest(line.Objective)
      if not map then
        changed = true
      elseif map ~= c.map or Tag(x, y) ~= Tag(c.x, c.y) then
        SetCoord(line, map, x, y, name, dist)
        Place(line)
        changed = true
      else
        c.dist = dist
      end
    end
  end
  if changed and not InCombatLockdown() and QT and QT.Update then pcall(QT.Update, QT) end
end

local hooked = false
local function Hook()
  if hooked or not QuestieLoader or not QuestieLoader.ImportModule then return end
  LB, TLP, TL = Import("LineBuilder"), Import("TrackerLinePool"), Import("TrackerLayout")
  DU, ZDB, QT = Import("DistanceUtils"), Import("ZoneDB"), Import("QuestieTracker")
  if not (LB and type(LB.AddObjective) == "function" and TLP and type(TLP.GetCurrentLine) == "function"
      and TL and DU and type(DU.GetNearestObjective) == "function" and ZDB and ZDB.GetUiMapIdByAreaId) then
    return
  end
  hooked = true
  hooksecurefunc(LB, "AddObjective", function(options) pcall(AfterAddObjective, options) end)
  if type(TLP.UpdateQuestLines) == "function" then
    hooksecurefunc(TLP, "UpdateQuestLines", function(questId) pcall(AfterUpdateQuestLines, questId) end)
  end
  if type(TLP.ResetLinesForChange) == "function" then
    hooksecurefunc(TLP, "ResetLinesForChange", function() if not InCombatLockdown() then pcall(AfterReset) end end)
  end
  if QT and type(QT.Update) == "function" then
    hooksecurefunc(QT, "Update", function() pcall(AfterUpdate) end)
  end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(4, function() pcall(Tick) end) end
  -- redraw once so lines already on screen get their tags
  if QT and QT.Update and C_Timer then C_Timer.After(1, function() pcall(QT.Update, QT) end) end
end

function ns.SetTrackerCoords(on)
  AskQuestDB.trackerCoords = on and true or false
  if not on then for line in pairs(decorated) do Undecorate(line) end end
  if QT and QT.Update and not InCombatLockdown() then pcall(QT.Update, QT) end
end

function ns.TrackerCoordsAvailable() return hooked end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() Hook() end)
