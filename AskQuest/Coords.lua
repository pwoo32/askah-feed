-- Coords.lua
-- "Go to coordinates" box: type "45 62" (or "Duskwood 45 62"), press Enter, and
-- the world map opens on that spot with a pulsing ping and a marker. It also
-- sets the game's own map pin (shows on the minimap too), adds a TomTom
-- waypoint if TomTom is installed, and an arrow in the box points the way
-- with the distance in yards.
-- Open it: /aq go (or /aq coords), middle-click or shift-click the minimap
-- button, or just type /aq 45 62. /way works too when no other addon owns it.
local _, ns = ...

local box, ping, marker
local target -- { map, x, y, name } with x, y in 0-1

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end

local function Norm(s) return (s or ""):lower():gsub("[^%a%d]", "") end

---------------------------------------------------------------------------
-- Zone name -> map ID
---------------------------------------------------------------------------
local mapsByName -- [normName] = { mapID, mapType }
local function BuildMaps()
  mapsByName = {}
  if not (C_Map and C_Map.GetMapInfo) then return end
  for id = 1, 2500 do
    local info = try(C_Map.GetMapInfo, id)
    if info and info.name and info.name ~= "" then
      local n = Norm(info.name)
      local t = info.mapType or 0
      local old = mapsByName[n]
      -- prefer zones (3), then dungeons/micro maps, then continents
      local rank = (t == 3) and 0 or (t >= 4) and 1 or 2
      if not old or rank < old[2] then mapsByName[n] = { id, rank } end
    end
  end
end

local function FindMap(text)
  if not mapsByName then BuildMaps() end
  local n = Norm(text)
  if n == "" then return nil end
  local alias = ns.ZoneAliases and ns.ZoneAliases[n]
  if alias then n = Norm(alias) end
  if mapsByName[n] then return mapsByName[n][1] end
  -- "the barrens" vs "barrens", "duskw" etc.: best partial match
  local best, bestRank, bestLen
  for name, v in pairs(mapsByName) do
    if #n >= 3 and (name:find(n, 1, true) or (#name >= 4 and n:find(name, 1, true))) then
      if not best or v[2] < bestRank or (v[2] == bestRank and #name < bestLen) then
        best, bestRank, bestLen = v[1], v[2], #name
      end
    end
  end
  return best
end

local function MapName(map)
  local info = map and C_Map and try(C_Map.GetMapInfo, map)
  return info and info.name or "?"
end

-- The map you mean when you type no zone: the zone open on the world map,
-- otherwise the zone you're standing in.
local function DefaultMap()
  if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID then
    -- whatever the map is showing right now: a zone, a city, a dungeon or a continent
    local id = WorldMapFrame:GetMapID()
    if id and id > 0 then return id end
  end
  return C_Map and try(C_Map.GetBestMapForUnit, "player")
end

-- "45 62", "45.2, 62.8", "Duskwood 45 62", "45 62 duskwood", "/way stv 30 40"
function ns.ParseCoords(text)
  text = (text or ""):gsub("^%s*/%a+%s*", ""):gsub(",", " ")
  local nums, rest = {}, text
  for num in text:gmatch("%-?%d+%.?%d*") do nums[#nums + 1] = tonumber(num) end
  if #nums < 2 then return nil, "type two numbers, like 45 62" end
  local x, y = nums[#nums - 1], nums[#nums]
  if x > 100 or y > 100 or x < 0 or y < 0 then return nil, "coordinates go from 0 to 100" end
  rest = rest:gsub("%-?%d+%.?%d*", " ")
  rest = strtrim((rest:gsub("%s+", " ")))
  local map
  if rest ~= "" then
    map = FindMap(rest)
    if not map then return nil, ("no zone called \"%s\""):format(rest) end
  else
    map = DefaultMap()
    if not map then return nil, "couldn't tell which zone; add the zone name" end
  end
  return map, x, y
end

---------------------------------------------------------------------------
-- Ping + marker on the world map
---------------------------------------------------------------------------
local function Canvas()
  if not WorldMapFrame then return end
  if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
  return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function MakeRing(parent, delay)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask") -- white disc
  t:SetVertexColor(1, 0.82, 0.1)
  t:SetAllPoints()
  t:SetAlpha(0)
  local ag = t:CreateAnimationGroup()
  local s = ag:CreateAnimation("Scale")
  if s.SetScaleFrom then s:SetScaleFrom(0.1, 0.1) s:SetScaleTo(1, 1)
  else s:SetFromScale(0.1, 0.1) s:SetToScale(1, 1) end
  s:SetDuration(1.2)
  s:SetStartDelay(delay)
  local a1 = ag:CreateAnimation("Alpha")
  a1:SetFromAlpha(0.75) a1:SetToAlpha(0)
  a1:SetDuration(1.2)
  a1:SetStartDelay(delay)
  ag:SetLooping("REPEAT")
  t.anim = ag
  return t
end

local function MakePing(canvas)
  ping = CreateFrame("Frame", nil, canvas)
  ping:SetSize(90, 90)
  ping.rings = { MakeRing(ping, 0), MakeRing(ping, 0.4), MakeRing(ping, 0.8) }

  marker = CreateFrame("Frame", nil, canvas)
  marker:SetSize(24, 24)
  local icon = marker:CreateTexture(nil, "OVERLAY")
  icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1") -- yellow star
  icon:SetAllPoints()
  marker:EnableMouse(true)
  marker:SetScript("OnEnter", function(self)
    if not target then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if target.label then GameTooltip:AddLine(target.label, 1, 1, 1) end
    GameTooltip:AddLine(("%s %.1f, %.1f"):format(target.name, target.x * 100, target.y * 100), 1, 0.82, 0)
    GameTooltip:AddLine("Set by AskQuest. /aq go clear removes it.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  marker:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- hide both when the map shows another zone, bring them back when it returns
  local watch = CreateFrame("Frame", nil, WorldMapFrame)
  watch:SetScript("OnUpdate", function()
    local here = target and WorldMapFrame:GetMapID() == target.map
    if here then
      if not marker:IsShown() then marker:Show() end
    elseif marker:IsShown() then
      marker:Hide() ping:Hide()
    end
  end)
end

local function StopPing()
  if not ping then return end
  for _, r in ipairs(ping.rings) do r.anim:Stop() r:SetAlpha(0) end
  ping:Hide()
end

local function ShowPing()
  local canvas = Canvas()
  if not canvas or not target then return end
  if not ping then MakePing(canvas) end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  local scale = (w and w > 0) and (w / 1000) or 1 -- keep the size steady on big canvases
  local lvl = canvas:GetFrameLevel() + 2000
  for _, f in ipairs({ ping, marker }) do
    f:SetParent(canvas)
    f:SetFrameLevel(lvl)
    f:ClearAllPoints()
    f:SetPoint("CENTER", canvas, "TOPLEFT", target.x * w, -target.y * h)
  end
  ping:SetSize(90 * scale, 90 * scale)
  marker:SetSize(24 * scale, 24 * scale)
  ping:Show() marker:Show()
  for _, r in ipairs(ping.rings) do r.anim:Stop() r.anim:Play() end
  if ping.timer then ping.timer:Cancel() end
  if C_Timer and C_Timer.NewTimer then ping.timer = C_Timer.NewTimer(6, StopPing) end
end

---------------------------------------------------------------------------
-- Go
---------------------------------------------------------------------------
local UpdateArrow

function ns.GoToCoords(text, fromMap)
  local map, x, y = ns.ParseCoords(text)
  if not map then ns.Print(x) return false end
  return ns.GoToPoint(map, x, y, nil, fromMap)
end

-- Ping a spot you already know: map ID, x/y in 0-100, optional label (e.g. "Kobold Vermin").
function ns.GoToPoint(map, x, y, label, fromMap)
  if not map or not x or not y then return false end
  target = { map = map, x = x / 100, y = y / 100, name = MapName(map), label = label }

  local pinned = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    pinned = pcall(function()
      if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then error("no") end
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
  end
  if TomTom and TomTom.AddWaypoint then
    if ns.lastTomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, ns.lastTomTom) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, x / 100, y / 100,
      { title = ("%s%s %.1f, %.1f"):format(label and (label .. " - ") or "", target.name, x, y), from = "AskQuest", crazy = true })
    if ok then ns.lastTomTom = uid pinned = true end
  end

  if InCombatLockdown() then
    ns.Print("in combat: open the map (M) after the fight to see the ping.")
  elseif WorldMapFrame then
    pcall(function()
      if not WorldMapFrame:IsShown() then
        if OpenWorldMap then OpenWorldMap(map) elseif ToggleWorldMap then ToggleWorldMap() end
      end
      if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(map) end
    end)
  end
  -- the canvas has its final size a frame after the map opens
  if C_Timer and C_Timer.After then C_Timer.After(0.05, ShowPing) else ShowPing() end

  ns.Print(("going to |cffffd200%s%s %.1f, %.1f|r%s"):format(label and (label .. ", ") or "", target.name, x, y,
    pinned and " - pinned on your map and minimap." or "."))
  if box and not fromMap then box:Show() UpdateArrow() end
  return true
end

function ns.ClearCoords()
  target = nil
  StopPing()
  if marker then marker:Hide() end
  if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  if ns.lastTomTom and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, ns.lastTomTom) end
  ns.lastTomTom = nil
  if box then UpdateArrow() end
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
local DIRS = { "north", "northwest", "west", "southwest", "south", "southeast", "east", "northeast" }

UpdateArrow = function()
  if not box then return end
  if not target then
    box.arrow:Hide()
    box.info:SetText("|cff888888x y, or zone x y. Enter to go.|r")
    return
  end
  local pos = C_Map and C_Map.GetPlayerMapPosition and try(C_Map.GetPlayerMapPosition, target.map, "player")
  local px, py
  if pos and pos.GetXY then px, py = pos:GetXY() end
  local w, h
  if C_Map and C_Map.GetMapWorldSize then w, h = try(C_Map.GetMapWorldSize, target.map) end
  if not px or (px == 0 and py == 0) or not w or w == 0 then
    box.arrow:Hide()
    box.info:SetText(("|cffffd200%s %.1f, %.1f|r  |cff888888not in your zone|r"):format(target.name, target.x * 100, target.y * 100))
    return
  end
  local east, south = (target.x - px) * w, (target.y - py) * h
  local yards = math.sqrt(east * east + south * south)
  if yards < 10 then
    box.arrow:Hide()
    box.info:SetText("|cff33ff33You're there!|r")
    return
  end
  local bearing = math.atan2(-east, -south) -- counter-clockwise from north, like GetPlayerFacing
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing then
    box.arrow:SetRotation(bearing - facing)
    box.arrow:Show()
  else
    box.arrow:Hide()
  end
  local dir = DIRS[(math.floor(((math.deg(bearing) % 360) + 22.5) / 45) % 8) + 1]
  box.info:SetText(("|cffffd200%s yd|r %s  |cff888888(%.1f, %.1f)|r"):format(
    ns.Commas and ns.Commas(math.floor(yards + 0.5)) or math.floor(yards + 0.5), dir, target.x * 100, target.y * 100))
end

local function Settings()
  AskQuestDB.coords = AskQuestDB.coords or {}
  return AskQuestDB.coords
end

local function CreateBox()
  box = CreateFrame("Frame", "AskQuestCoordsBox", UIParent, ns.WindowTemplate())
  box:SetSize(250, 92)
  box:SetFrameStrata("HIGH")
  box:SetClampedToScreen(true)
  box:SetMovable(true)
  box:EnableMouse(true)
  box:RegisterForDrag("LeftButton")
  box:SetScript("OnDragStart", box.StartMoving)
  box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    Settings().pos = { p, rp, x, y }
  end)
  local pos = Settings().pos
  if pos then box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else box:SetPoint("TOP", 0, -120) end
  if ns.Skin then ns.Skin(box, "Go to coordinates", 26) end
  if box.closeButton then
    box.closeButton:HookScript("OnClick", function() Settings().shown = false end)
  end

  local edit = CreateFrame("EditBox", "AskQuestCoordsEdit", box, "InputBoxTemplate")
  edit:SetSize(140, 20)
  edit:SetPoint("TOPLEFT", 16, -36)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(60)
  edit:SetScript("OnEnterPressed", function(self)
    if ns.GoToCoords(self:GetText()) then self:HighlightText() end
    self:ClearFocus()
  end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box.edit = edit

  local go = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  go:SetSize(36, 22)
  go:SetPoint("LEFT", edit, "RIGHT", 6, 0)
  go:SetText("Go")
  go:SetScript("OnClick", function() ns.GoToCoords(edit:GetText()) end)

  local clear = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  clear:SetSize(22, 22)
  clear:SetPoint("LEFT", go, "RIGHT", 2, 0)
  clear:SetText("x")
  clear:SetScript("OnClick", function() edit:SetText("") ns.ClearCoords() end)
  clear:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText("Clear the waypoint") GameTooltip:Show()
  end)
  clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local arrow = box:CreateTexture(nil, "ARTWORK")
  arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  arrow:SetSize(26, 26)
  arrow:SetPoint("BOTTOMLEFT", 10, 8)
  box.arrow = arrow

  local info = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
  info:SetPoint("RIGHT", box, "RIGHT", -10, 0)
  info:SetJustifyH("LEFT")
  info:SetWordWrap(false)
  box.info = info

  local elapsed = 0
  box:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    UpdateArrow()
  end)
  UpdateArrow()
end

function ns.ShowCoordsBox(focus)
  if not box then CreateBox() end
  box:Show()
  Settings().shown = true
  if focus then box.edit:SetFocus() end
end

function ns.ToggleCoordsBox()
  if box and box:IsShown() then
    box:Hide() Settings().shown = false
  else
    ns.ShowCoordsBox(true)
  end
end

---------------------------------------------------------------------------
-- /way (only if no other addon has it) and reopening the box after /reload
---------------------------------------------------------------------------
local function SlashTaken(cmd)
  cmd = cmd:upper()
  for key in pairs(SlashCmdList) do
    for i = 1, 9 do
      local s = _G["SLASH_" .. key .. i]
      if not s then break end
      if s:upper() == cmd then return true end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- The box on the world map itself: open the map (M), click the box, type
-- "45 62" (or "Duskwood 45 62"), press Enter. Shows the coordinates under
-- your mouse next to it.
---------------------------------------------------------------------------
local mapBox
local function CreateMapBox()
  if mapBox or not WorldMapFrame then return end
  local host = WorldMapFrame.ScrollContainer or WorldMapFrame
  mapBox = CreateFrame("Frame", "AskQuestMapCoords", host, ns.WindowTemplate())
  mapBox:SetSize(250, 30)
  mapBox:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 6, 6)
  mapBox:SetFrameLevel((host:GetFrameLevel() or 1) + 2100)
  if mapBox.SetBackdrop then
    mapBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    mapBox:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    mapBox:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  end
  mapBox:EnableMouse(true)

  local label = mapBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", 8, 0)
  label:SetText("Go to:")

  local edit = CreateFrame("EditBox", "AskQuestMapCoordsEdit", mapBox, "InputBoxTemplate")
  edit:SetSize(110, 18)
  edit:SetPoint("LEFT", label, "RIGHT", 8, 0)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(60)
  local hint = edit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("45 62  then Enter")
  local function Hint() hint:SetShown(edit:GetText() == "" and not edit:HasFocus()) end
  edit:SetScript("OnTextChanged", Hint)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() Hint() end)
  edit:SetScript("OnEditFocusLost", Hint)
  edit:SetScript("OnEnterPressed", function(self)
    if ns.GoToCoords(self:GetText(), true) then self:HighlightText() end
    self:ClearFocus()
  end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local cursor = mapBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cursor:SetPoint("LEFT", edit, "RIGHT", 8, 0)
  cursor:SetPoint("RIGHT", mapBox, "RIGHT", -8, 0)
  cursor:SetJustifyH("LEFT")
  local sc = WorldMapFrame.ScrollContainer
  local t = 0
  mapBox:SetScript("OnUpdate", function(_, dt)
    t = t + dt
    if t < 0.05 then return end
    t = 0
    local x, y
    if sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver() then x, y = sc:GetNormalizedCursorPosition() end
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      cursor:SetText(("|cff888888mouse|r %.1f, %.1f"):format(x * 100, y * 100))
    else
      cursor:SetText("")
    end
  end)
  -- clicking the map elsewhere takes the typing focus away
  WorldMapFrame:HookScript("OnHide", function() edit:ClearFocus() end)
  mapBox.edit = edit
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "Blizzard_WorldMap" then CreateMapBox() end
    return
  end
  CreateMapBox()
  if not SlashTaken("/way") then
    SLASH_ASKQUESTWAY1 = "/way"
    SlashCmdList.ASKQUESTWAY = function(msg)
      msg = strtrim(msg or "")
      if msg == "" then ns.ShowCoordsBox(true)
      elseif msg:lower() == "clear" or msg:lower() == "reset" then ns.ClearCoords()
      else ns.GoToCoords(msg) end
    end
  end
  if AskQuestDB.coords and AskQuestDB.coords.shown then ns.ShowCoordsBox(false) end
end)
