-- Transport.lua
-- Boats, zeppelins and the tram: where each dock goes.
--  * World map: a marker on every dock with a label ("Boat: Theramore").
--    Hover it for the full route. Continent maps show the markers too.
--  * In the world: walk up to a dock and a banner says where its boats go.
--  * /aq docks          list the docks in your zone
--    /aq docks on|off   markers on the world map
--    /aq dock here      move the nearest marker to where you stand (fixes a
--                       spot that is a bit off; saved)
--    /aq dock add Text  add your own marker here, e.g. /aq dock add Boat to Riverglades
--    /aq dock reset     undo your moves and added markers
local _, ns = ...

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end

-- Classic Era uiMapIDs
local M = {
  Wetlands = 1437, Darkshore = 1439, Teldrassil = 1438, Dustwallow = 1445,
  Hillsbrad = 1424, Feralas = 1444, Durotar = 1411, Tirisfal = 1420,
  STV = 1434, Barrens = 1413, Tanaris = 1446, Stormwind = 1453, Ironforge = 1455,
}

-- kind: B boat, Z zeppelin, T tram. side: A, H or N (both).
-- approx = the spot is a best guess; /aq dock here fixes it.
-- Routes follow the WoW Forever travel guides (Oct-Nov 2026).
local DOCKS = {
  { id = "sw_harbor", map = M.Stormwind, x = 0.22, y = 0.58, kind = "B", side = "A", approx = true,
    name = "Stormwind Harbor", go = { "Auberdine (Darkshore)" },
    note = "New in Forever: straight boat to Darkshore, no Wetlands run." },
  { id = "menethil", map = M.Wetlands, x = 0.049, y = 0.60, kind = "B", side = "A",
    name = "Menethil Harbor", go = { "Southshore, then Auberdine (loop boat)", "Theramore (Dustwallow Marsh)" },
    note = "The Forever loop boat runs Menethil > Southshore > Auberdine. Theramore is the Classic boat; check the dock sign." },
  { id = "southshore", map = M.Hillsbrad, x = 0.535, y = 0.565, kind = "B", side = "A", approx = true,
    name = "Southshore dock", go = { "Auberdine, then Menethil (loop boat)" },
    note = "New in Forever: part of the Menethil-Southshore-Auberdine loop." },
  { id = "auberdine", map = M.Darkshore, x = 0.324, y = 0.438, kind = "B", side = "A",
    name = "Auberdine docks", go = { "Stormwind Harbor", "Menethil, then Southshore (loop boat)", "Rut'theran Village (Teldrassil)" },
    note = "Three piers. The sign at each pier says which boat stops there." },
  { id = "ruttheran", map = M.Teldrassil, x = 0.552, y = 0.965, kind = "B", side = "A", approx = true,
    name = "Rut'theran Village dock", go = { "Auberdine (Darkshore)" } },
  { id = "theramore", map = M.Dustwallow, x = 0.716, y = 0.564, kind = "B", side = "A",
    name = "Theramore dock", go = { "Menethil Harbor (Wetlands)" } },
  { id = "feathermoon", map = M.Feralas, x = 0.310, y = 0.398, kind = "B", side = "A",
    name = "Feathermoon Stronghold dock", go = { "The Forgotten Coast (mainland Feralas)" } },
  { id = "forgottencoast", map = M.Feralas, x = 0.434, y = 0.428, kind = "B", side = "A",
    name = "Forgotten Coast dock", go = { "Feathermoon Stronghold (island)" } },
  { id = "ratchet", map = M.Barrens, x = 0.636, y = 0.386, kind = "B", side = "N",
    name = "Ratchet dock", go = { "Booty Bay (Stranglethorn)" } },
  { id = "bootybay", map = M.STV, x = 0.259, y = 0.731, kind = "B", side = "N",
    name = "Booty Bay dock", go = { "Ratchet (The Barrens)" } },
  { id = "steamwheedle", map = M.Tanaris, x = 0.686, y = 0.230, kind = "B", side = "N",
    name = "Steamwheedle Port", go = { "Powderfuse Port (Riverglades)" },
    note = "New in Forever: the only way to the Riverglades." },
  { id = "powderfuse", mapName = "Riverglades", x = 0.806, y = 0.546, kind = "B", side = "N",
    name = "Powderfuse Port", go = { "Steamwheedle Port (Tanaris)" },
    note = "No flight master here." },
  { id = "tram_sw", map = M.Stormwind, x = 0.665, y = 0.340, kind = "T", side = "A", approx = true,
    name = "Deeprun Tram", go = { "Ironforge" } },
  { id = "tram_if", map = M.Ironforge, x = 0.766, y = 0.510, kind = "T", side = "A",
    name = "Deeprun Tram", go = { "Stormwind" } },
  { id = "zep_org", map = M.Durotar, x = 0.506, y = 0.126, kind = "Z", side = "H",
    name = "Orgrimmar zeppelin tower", go = { "Undercity (Tirisfal)", "Grom'gol (Stranglethorn)" } },
  { id = "zep_uc", map = M.Tirisfal, x = 0.607, y = 0.588, kind = "Z", side = "H",
    name = "Undercity zeppelin tower", go = { "Orgrimmar (Durotar)", "Grom'gol (Stranglethorn)" } },
  { id = "zep_gg", map = M.STV, x = 0.314, y = 0.296, kind = "Z", side = "H",
    name = "Grom'gol zeppelin tower", go = { "Orgrimmar (Durotar)", "Undercity (Tirisfal)" } },
}

local KIND = {
  B = { word = "Boat", r = 0.25, g = 0.65, b = 1 },
  Z = { word = "Zeppelin", r = 1, g = 0.45, b = 0.2 },
  T = { word = "Tram", r = 0.8, g = 0.8, b = 0.8 },
  C = { word = "Marker", r = 0.3, g = 1, b = 0.4 },
}

-- "Boat to Theramore", or your own text as typed
local function Route(d, g) return d.mine and g or (KIND[d.kind].word .. " to " .. g) end

local function DB()
  AskQuestDB = AskQuestDB or {}
  AskQuestDB.docks = AskQuestDB.docks or {}
  local d = AskQuestDB.docks
  d.fix = d.fix or {}
  d.add = d.add or {}
  return d
end

local mapIDByName = {}
local function MapFor(d)
  if d.map then return d.map end
  if not d.mapName then return nil end
  if mapIDByName[d.mapName] == nil then
    mapIDByName[d.mapName] = false
    for id = 1, 2500 do
      local info = try(C_Map.GetMapInfo, id)
      if info and info.name == d.mapName and (info.mapType or 0) == 3 then mapIDByName[d.mapName] = id break end
    end
  end
  return mapIDByName[d.mapName] or nil
end

local mySide
local function MySide()
  if not mySide then
    local f = UnitFactionGroup and UnitFactionGroup("player")
    mySide = (f == "Horde") and "H" or "A"
  end
  return mySide
end

-- every dock with the player's moves applied, plus their own markers
local function All()
  local db, out = DB(), {}
  for _, d in ipairs(DOCKS) do
    local f = db.fix[d.id]
    local e = setmetatable({}, { __index = d })
    if f then e.x, e.y, e.map, e.approx, e.fixed = f.x, f.y, f.map or d.map, false, true end
    out[#out + 1] = e
  end
  for i, a in ipairs(db.add) do
    out[#out + 1] = { id = "add" .. i, map = a.map, x = a.x, y = a.y, kind = "C", side = "N",
      name = "Your marker", go = { a.text }, mine = true }
  end
  return out
end

local function Visible(d)
  local db = DB()
  if d.side == "N" or d.side == MySide() then return true end
  return db.showOther
end

local function Tooltip(owner, d)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local k = KIND[d.kind]
  GameTooltip:AddLine(d.name, 1, 0.82, 0)
  for _, g in ipairs(d.go) do GameTooltip:AddLine(Route(d, g), 1, 1, 1) end
  if d.side == "H" then GameTooltip:AddLine("Horde only", 1, 0.3, 0.3)
  elseif d.side == "A" then GameTooltip:AddLine("Alliance", 0.4, 0.6, 1) end
  if d.note then GameTooltip:AddLine(d.note, 0.7, 0.7, 0.7, true) end
  if d.approx then GameTooltip:AddLine("Spot is approximate. Stand on the dock and type /aq dock here to fix it.", 0.6, 0.6, 0.6, true) end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- World map markers
---------------------------------------------------------------------------
local pins, used = {}, 0

local function Canvas()
  if not WorldMapFrame then return end
  if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
  return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function GetPin(canvas)
  used = used + 1
  local p = pins[used]
  if not p then
    p = CreateFrame("Frame", nil, canvas)
    p:SetSize(18, 18)
    p:SetFrameStrata("HIGH")
    p:EnableMouse(true)
    local disc = p:CreateTexture(nil, "ARTWORK")
    disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    disc:SetAllPoints()
    p.disc = disc
    local edge = p:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    edge:SetVertexColor(0, 0, 0, 0.9)
    edge:SetPoint("TOPLEFT", -2, 2) edge:SetPoint("BOTTOMRIGHT", 2, -2)
    local letter = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    letter:SetPoint("CENTER", 0, 0)
    letter:SetTextColor(0, 0, 0)
    p.letter = letter
    local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", p, "RIGHT", 3, 0)
    label:SetJustifyH("LEFT")
    label:SetShadowOffset(1, -1)
    p.label = label
    p:SetScript("OnEnter", function(self) if self.dock then Tooltip(self, self.dock) end end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[used] = p
  end
  return p
end

local function ShortGo(d)
  local parts = {}
  for _, g in ipairs(d.go) do parts[#parts + 1] = (g:gsub("%s*%b()", "")) end
  return table.concat(parts, " / ")
end

-- place (x, y) of zone `from` on map `to` (for continent maps)
local function Project(from, x, y, to)
  if from == to then return x, y end
  if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  local inst, wpos = try(C_Map.GetWorldPosFromMapPos, from, CreateVector2D(x, y))
  if not wpos then return end
  local _, pos = try(C_Map.GetMapPosFromWorldPos, inst, wpos, to)
  if not pos then return end
  local px, py = pos:GetXY()
  if px and px > 0 and px < 1 and py > 0 and py < 1 then return px, py end
end

local lastMap, lastW
local function Refresh()
  local canvas = Canvas()
  if not canvas then return end
  for i = 1, used do pins[i]:Hide() end
  used = 0
  if DB().hide then return end
  local mapID = WorldMapFrame:GetMapID()
  if not mapID then return end
  local info = try(C_Map.GetMapInfo, mapID)
  local zoneView = info and (info.mapType or 0) >= 3
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  for _, d in ipairs(All()) do
    local dm = MapFor(d)
    if dm and Visible(d) then
      local x, y
      if dm == mapID then x, y = d.x, d.y
      elseif not zoneView then x, y = Project(dm, d.x, d.y, mapID) end
      if x then
        local p = GetPin(canvas)
        local k = KIND[d.kind]
        p.dock = d
        p.disc:SetVertexColor(k.r, k.g, k.b)
        p.letter:SetText(d.kind)
        p:SetScale(zoneView and 1 or 0.75)
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", x * w / p:GetScale(), -y * h / p:GetScale())
        if zoneView then
          p.label:SetText(d.mine and ShortGo(d) or ("|cffffd200%s:|r %s"):format(k.word, ShortGo(d)))
          p.label:Show()
        else
          p.label:Hide()
        end
        p:Show()
      end
    end
  end
end
ns.RefreshDocks = Refresh

local function HookMap()
  if not WorldMapFrame then return end
  local watch = CreateFrame("Frame", nil, WorldMapFrame)
  watch:SetScript("OnUpdate", function()
    local id = WorldMapFrame:GetMapID()
    local c = Canvas()
    local cw = c and c:GetWidth()
    if id ~= lastMap or cw ~= lastW then lastMap, lastW = id, cw Refresh() end
  end)
  WorldMapFrame:HookScript("OnShow", function() lastMap = nil if ns.SyncDockToggle then ns.SyncDockToggle() end end)

  -- "Boats" checkbox in the map's bottom-right corner turns the markers on/off
  local host = WorldMapFrame.ScrollContainer or WorldMapFrame
  local box = CreateFrame("Frame", "AskQuestDockToggle", host, ns.WindowTemplate and ns.WindowTemplate())
  box:SetSize(150, 26)
  box:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -6, 6)
  box:SetFrameLevel((host:GetFrameLevel() or 1) + 2100)
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    box:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  end
  box:EnableMouse(true)
  local cb = CreateFrame("CheckButton", "AskQuestDockToggleCheck", box, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("LEFT", 3, 0)
  local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  label:SetText("Boats & zeppelins")
  cb:SetScript("OnClick", function(self)
    DB().hide = not self:GetChecked() or nil
    Refresh()
  end)
  local function Tip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Dock markers", 1, 0.82, 0)
    GameTooltip:AddLine("Show where each boat, zeppelin and tram goes.", 1, 1, 1, true)
    GameTooltip:AddLine("Also: /aq docks on|off", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  cb:SetScript("OnEnter", Tip)
  box:SetScript("OnEnter", Tip)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  box:SetScript("OnLeave", function() GameTooltip:Hide() end)
  box:SetScript("OnMouseUp", function() cb:Click() end)
  ns.SyncDockToggle = function() cb:SetChecked(not DB().hide) end
  ns.SyncDockToggle()
end

---------------------------------------------------------------------------
-- Banner when you walk up to a dock
---------------------------------------------------------------------------
local banner, nearID

local function MakeBanner()
  banner = CreateFrame("Frame", "AskQuestDockBanner", UIParent, ns.WindowTemplate and ns.WindowTemplate())
  banner:SetSize(360, 60)
  banner:SetPoint("TOP", UIParent, "TOP", 0, -120)
  banner:SetFrameStrata("MEDIUM")
  if banner.SetBackdrop then
    banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    banner:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    banner:SetBackdropBorderColor(0.25, 0.65, 1, 1)
  end
  banner:SetMovable(true)
  banner:EnableMouse(true)
  banner:RegisterForDrag("LeftButton")
  banner:SetScript("OnDragStart", banner.StartMoving)
  banner:SetScript("OnDragStop", banner.StopMovingOrSizing)
  banner:SetScript("OnEnter", function(self) if self.dock then Tooltip(self, self.dock) end end)
  banner:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local t = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -9)
  t:SetPoint("TOPRIGHT", -24, -9)
  t:SetJustifyH("LEFT")
  banner.title = t
  local b = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
  b:SetPoint("RIGHT", -10, 0)
  b:SetJustifyH("LEFT")
  banner.body = b
  local x = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
  x:SetSize(22, 22)
  x:SetPoint("TOPRIGHT", 0, 0)
  x:SetScript("OnClick", function() banner:Hide() end)
  banner:Hide()
end

local function ShowBanner(d)
  if not banner then MakeBanner() end
  local k = KIND[d.kind]
  banner.dock = d
  banner.title:SetText(d.name)
  local lines = {}
  for _, g in ipairs(d.go) do lines[#lines + 1] = d.mine and g or ("|cffffd200" .. k.word .. " to|r " .. g) end
  banner.body:SetText(table.concat(lines, "\n"))
  banner:SetHeight(26 + 14 * #lines)
  if banner.SetBackdropBorderColor then banner:SetBackdropBorderColor(k.r, k.g, k.b, 1) end
  banner:Show()
end

local function PlayerAt()
  local map = try(C_Map.GetBestMapForUnit, "player")
  if not map then return end
  local pos = try(C_Map.GetPlayerMapPosition, map, "player")
  if not (pos and pos.GetXY) then return end
  local x, y = pos:GetXY()
  if not x or (x == 0 and y == 0) then return end
  return map, x, y
end

local function Yards(map, x1, y1, x2, y2)
  local w, h = try(C_Map.GetMapWorldSize, map)
  if not w or w == 0 then return end
  local dx, dy = (x2 - x1) * w, (y2 - y1) * h
  return math.sqrt(dx * dx + dy * dy)
end

local function Nearest(map, x, y, list)
  local best, bestY
  for _, d in ipairs(list or All()) do
    if MapFor(d) == map then
      local yd = Yards(map, x, y, d.x, d.y)
      if yd and (not bestY or yd < bestY) then best, bestY = d, yd end
    end
  end
  return best, bestY
end

local tick = 0
local function OnTick(_, e)
  tick = tick + e
  if tick < 1 then return end
  tick = 0
  if DB().noBanner then return end
  local map, x, y = PlayerAt()
  if not map then return end
  local d, yd = Nearest(map, x, y)
  local reach = d and (d.approx and 130 or 70)
  if d and yd <= reach and Visible(d) then
    if nearID ~= d.id then
      nearID = d.id
      ShowBanner(d)
      ns.Print(("%s: %s"):format(d.name, table.concat(d.go, "; ")))
    end
  elseif nearID and (not d or yd > (reach or 0) + 40) then
    nearID = nil
    if banner then banner:Hide() end
  end
end

---------------------------------------------------------------------------
-- Slash: /aq docks, /aq dock here, /aq dock add ..., /aq dock reset
---------------------------------------------------------------------------
function ns.DockCommand(rest, raw)
  local db = DB()
  if rest == "off" then db.hide = true Refresh() if ns.SyncDockToggle then ns.SyncDockToggle() end ns.Print("dock markers hidden on the map. /aq docks on shows them.") return end
  if rest == "on" then db.hide = nil Refresh() if ns.SyncDockToggle then ns.SyncDockToggle() end ns.Print("dock markers shown on the map.") return end
  if rest == "banner off" then db.noBanner = true if banner then banner:Hide() end ns.Print("dock banner off.") return end
  if rest == "banner on" then db.noBanner = nil nearID = nil ns.Print("dock banner on.") return end
  if rest == "horde on" or rest == "all" then db.showOther = true Refresh() ns.Print("showing the other faction's zeppelins and docks too.") return end
  if rest == "horde off" then db.showOther = nil Refresh() ns.Print("showing your faction's and neutral docks.") return end
  if rest == "reset" then db.fix, db.add = {}, {} Refresh() ns.Print("dock markers reset.") return end
  local map, x, y = PlayerAt()
  if rest == "here" then
    if not map then ns.Print("can't read your position here.") return end
    local list = {}
    for _, d in ipairs(All()) do if not d.mine then list[#list + 1] = d end end
    local d, yd = Nearest(map, x, y, list)
    if not d or yd > 500 then ns.Print("no known dock within 500 yards. Use /aq dock add <where it goes>.") return end
    db.fix[d.id] = { map = map, x = x, y = y }
    nearID = nil
    Refresh()
    ns.Print(("moved %s to %.1f, %.1f (was %.0f yards off)."):format(d.name, x * 100, y * 100, yd))
    return
  end
  local text = raw and raw:match("^[Dd][Oo][Cc][Kk][Ss]?%s+[Aa][Dd][Dd]%s+(.+)$")
  if text then
    if not map then ns.Print("can't read your position here.") return end
    db.add[#db.add + 1] = { map = map, x = x, y = y, text = text }
    Refresh()
    ns.Print(("added a marker here: %s."):format(text))
    return
  end
  -- list this zone (or all when nothing here)
  local here = map
  local n = 0
  for _, d in ipairs(All()) do
    if MapFor(d) == here and Visible(d) then
      n = n + 1
      print(("  |cffffd200%s|r %.0f, %.0f: %s"):format(d.name, d.x * 100, d.y * 100, Route(d, table.concat(d.go, "; "))))
    end
  end
  if n == 0 then
    ns.Print("no boats, zeppelins or trams in this zone. All of them:")
    for _, d in ipairs(All()) do
      if Visible(d) then print(("  |cffffd200%s|r: %s"):format(d.name, table.concat(d.go, "; "))) end
    end
  end
  print("  |cff888888/aq docks on|off (map markers), /aq dock here (fix a spot), /aq dock add <text>, /aq docks banner off, /aq docks horde on|r")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  HookMap()
  ev:SetScript("OnUpdate", OnTick)
end)
