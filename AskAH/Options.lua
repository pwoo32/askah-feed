-- Options.lua
-- AskAH's page in Esc > Options > AddOns: every on/off switch in one place,
-- so you don't need to remember slash commands. /askah options opens it.
local _, ns = ...

local function DB() AskAHDB = AskAHDB or {}; return AskAHDB end
local function TT() local d = DB(); d.tt = d.tt or {}; return d.tt end

-- { label, get, set } or a heading string
local OPTIONS = {
  "Item tooltips",
  { "Show AskAH info on item tooltips", function() return DB().tooltip ~= false end, function(v) DB().tooltip = v end },
  { "Always show full detail (no need to hold Shift)", function() return DB().ttDetail == "always" end, function(v) DB().ttDetail = v and "always" or nil end },
  { "Show the \"Hold Shift for more\" hint", function() return DB().ttHint ~= false end, function(v) DB().ttHint = v end },
  { "Auction house and vendor prices", function() return TT().prices ~= false end, function(v) TT().prices = v end },
  { "Gear upgrade check", function() return TT().gear ~= false end, function(v) TT().gear = v end },
  { "Profession leveling guides and recipes", function() return TT().prof ~= false end, function(v) TT().prof = v end },
  { "Crafting cost, reagent uses and item sets", function() return TT().craft ~= false end, function(v) TT().craft = v end },
  "Auction house",
  { "Pop up the deals window when you open the AH", function() return DB().dealsPopup ~= false end, function(v) DB().dealsPopup = v end },
  { "Scan the AH automatically (at most every 15 min)", function() return DB().autoScan ~= false end, function(v) DB().autoScan = v end },
  { "Open the guide next to the AH", function() return DB().openWithAH == true end, function(v) DB().openWithAH = v end },
  "Other",
  { "Minimap button", function() return not (DB().minimap and DB().minimap.hide) end,
    function(v) DB().minimap = DB().minimap or {}; DB().minimap.hide = (not v) or nil; if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end },
}

local panel = CreateFrame("Frame")
panel.name = "AskAH"
panel:Hide()
local boxes = {}

local function Build()
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AskAH")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  sub:SetText("Prices, sell advice and upgrade checks on item tooltips. Type /askah help for commands.")
  local y = -64
  for _, o in ipairs(OPTIONS) do
    if type(o) == "string" then
      y = y - 8
      local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      h:SetPoint("TOPLEFT", 16, y)
      h:SetText(o)
      y = y - 22
    else
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
end

panel:SetScript("OnShow", function()
  if #boxes == 0 then Build() end
  for _, cb in ipairs(boxes) do cb:SetChecked(cb.get() and true or false) end
end)

local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, "AskAH")
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
