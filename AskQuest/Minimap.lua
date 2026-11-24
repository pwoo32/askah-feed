-- Minimap.lua
-- A round button on the minimap edge, like other addons have.
-- Left-click: open/close the chart. Right-click: best quest here.
-- Drag it around the minimap; the spot is saved.
local _, ns = ...

local button
local RADIUS = 105 -- distance from the minimap centre; fits the default round minimap

local function Settings()
  AskQuestDB.minimap = AskQuestDB.minimap or {}
  local s = AskQuestDB.minimap
  if type(s.angle) ~= "number" then s.angle = 200 end
  return s
end

local function Place()
  local s = Settings()
  local a = math.rad(s.angle)
  local w = (Minimap:GetWidth() or 140) / 2 + 10
  local r = math.max(w, 80)
  if r > RADIUS + 20 then r = RADIUS end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function Dragging(self)
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  Settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  Place()
end

local function Create()
  button = CreateFrame("Button", "AskQuestMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon") -- the yellow "!"
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, which)
    if which == "MiddleButton" or (which == "LeftButton" and IsShiftKeyDown()) then
      if ns.ToggleCoordsBox then ns.ToggleCoordsBox() end
    elseif which == "RightButton" then ns.ShowInWindow("best quest here")
    else ns.ToggleWindow() end
  end)
  button:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", Dragging)
  end)
  button:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("AskQuest", 0.2, 0.8, 1)
    GameTooltip:AddLine("Left-click: open the quest chart", 1, 1, 1)
    GameTooltip:AddLine("Right-click: best quests here", 1, 1, 1)
    GameTooltip:AddLine("Shift-click or middle-click: go to coordinates", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Hide it in Esc > Options > AddOns > AskQuest", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
  if not Minimap then return end
  if not button then Create() end
  if Settings().hide then
    button:Hide()
  else
    Place()
    button:Show()
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  if not Minimap then return end
  if not button then Create() end
  if Settings().hide then button:Hide() else Place() button:Show() end
end)
