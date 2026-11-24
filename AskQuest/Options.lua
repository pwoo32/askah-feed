-- Options.lua
-- AskQuest's page in Esc > Options > AddOns. /aq options opens it.
local _, ns = ...

local function DB() AskQuestDB = AskQuestDB or {}; return AskQuestDB end

local OPTIONS = {
  { "Show the reward and worth-it panel at quest givers and in the quest log",
    function() return DB().info ~= false end, function(v) DB().info = v end },
  { "Rewards in Questie's map and minimap icon tooltips (hold Shift)",
    function() return DB().questieRewards ~= false end, function(v) DB().questieRewards = v end },
  { "Minimap button", function() return not (DB().minimap and DB().minimap.hide) end,
    function(v) DB().minimap = DB().minimap or {}; DB().minimap.hide = not v; if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end },
  { "Coordinates of the nearest objective spot in Questie's quest tracker (click to ping the map)",
    function() return DB().trackerCoords ~= false end, function(v) if ns.SetTrackerCoords then ns.SetTrackerCoords(v) else DB().trackerCoords = v end end },
  { "Boat, zeppelin and tram markers on the world map", function() return not (DB().docks and DB().docks.hide) end,
    function(v) DB().docks = DB().docks or {}; DB().docks.hide = (not v) or nil; if ns.RefreshDocks then ns.RefreshDocks() end; if ns.SyncDockToggle then ns.SyncDockToggle() end end },
  { "Banner when you walk onto a dock", function() return not (DB().docks and DB().docks.noBanner) end,
    function(v) DB().docks = DB().docks or {}; DB().docks.noBanner = (not v) or nil end },
}

local panel = CreateFrame("Frame")
panel.name = "AskQuest"
panel:Hide()
local boxes = {}

local function Build()
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AskQuest")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Which quest is worth it: XP, gold, rewards and chains. Type /aq help for commands.")
  local y = -64
  for _, o in ipairs(OPTIONS) do
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 24, y)
    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    label:SetText(o[1])
    cb:SetScript("OnClick", function(self) o[3](self:GetChecked() and true or false) end)
    cb.get = o[2]
    boxes[#boxes + 1] = cb
    y = y - 26
  end
end

panel:SetScript("OnShow", function()
  if #boxes == 0 then Build() end
  for _, cb in ipairs(boxes) do cb:SetChecked(cb.get() and true or false) end
end)

local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, "AskQuest")
  Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
  if category and Settings.OpenToCategory then
    Settings.OpenToCategory(category.GetID and category:GetID() or category)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    ns.Print("couldn't open the settings page. Find it in Esc > Options > AddOns.")
  end
end
