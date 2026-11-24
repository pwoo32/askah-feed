-- UI.lua
-- Movable window with four tabs: Guide, Character, Bags, Prices.
-- The search box filters whichever tab is open.
local _, ns = ...

local window, scrollChild, searchBox, textLines, scroll
local currentTopic
local mode = "guide"
local tabs = {}

local function Money(c) return ns.Data.Money(c) end

---------------------------------------------------------------------------
-- Text for each tab
---------------------------------------------------------------------------
local function GuideText(query)
  -- Only gold routes and leveling guides for this character (Knowledge.lua).
  local ok, entries = pcall(function()
    return (query ~= "") and ns.Search(query) or ns.Routes.Entries()
  end)
  if not ok then
    return "|cffff6060The guide hit an error:|r\n" .. tostring(entries) .. "\n\nPlease send this line to Claude."
  end
  local out, lastTopic = {}, nil
  for _, e in ipairs(entries) do
    if e.topic ~= lastTopic then
      out[#out + 1] = "\n|cff33ccff" .. e.topic .. "|r"
      lastTopic = e.topic
    end
    out[#out + 1] = "|cffffd200" .. e.q .. "|r"
    out[#out + 1] = e.a .. "\n"
  end
  if #out == 0 then return "Nothing matches. Try other words." end
  return table.concat(out, "\n")
end

local STAT_ORDER = {
  "level", "health", "power", "Strength", "Agility", "Stamina", "Intellect", "Spirit",
  "Armor", "AttackPower", "Defense", "Dodge", "Parry", "Block", "BlockValue", "Crit", "WeaponSpeed",
}
local PCT = { Dodge = true, Parry = true, Block = true, Crit = true }

local function StatsText()
  local c = ns.Data.Char()
  local s = c.stats
  if not s then return "No stats yet. Leave combat for a second, or type /askah stats." end
  local out = {
    ("|cff33ccff%s|r  level %s %s %s"):format(UnitName("player") or "", s.level or "?", s.race or "", s.class or ""),
    ("Gold: %s"):format(Money(c.money)),
    "",
  }
  for _, k in ipairs(STAT_ORDER) do
    local v = s[k]
    if v ~= nil then
      if PCT[k] then v = ("%.2f%%"):format(v)
      elseif type(v) == "number" and v % 1 ~= 0 then v = ("%.2f"):format(v) end
      out[#out + 1] = ("|cffffd200%s|r  %s"):format(k, tostring(v))
    end
  end
  if c.professions and next(c.professions) then
    out[#out + 1] = "\n|cff33ccffProfessions|r"
    for name, p in pairs(c.professions) do
      out[#out + 1] = ("%s  %s/%s"):format(name, p.skill or "?", p.max or "?")
    end
  end
  if c.equipped and #c.equipped > 0 then
    out[#out + 1] = "\n|cff33ccffEquipped|r"
    for _, e in ipairs(c.equipped) do
      out[#out + 1] = ("%s: %s"):format(e.slot, e.link or e.n or "?")
    end
  end
  out[#out + 1] = "\n|cff888888Updated " .. ns.Data.Ago(c.updated) .. "|r"
  return table.concat(out, "\n")
end

local function ItemList(items, query, prices)
  local rows = {}
  for itemID, e in pairs(items or {}) do
    local name = e.n or ("item " .. itemID)
    if query == "" or name:lower():find(query, 1, true) then
      rows[#rows + 1] = { n = name, link = e.link, c = e.c, p = prices[itemID] and prices[itemID].p }
    end
  end
  table.sort(rows, function(a, b) return a.n < b.n end)
  local out = {}
  for _, r in ipairs(rows) do
    local line = ("%dx %s"):format(r.c, r.link or r.n)
    if r.p then line = line .. "  |cff888888" .. Money(r.p * r.c) .. "|r" end
    out[#out + 1] = line
  end
  return out
end

local function BagsText(query)
  local c = ns.Data.Char()
  local prices = ns.Data.Prices("faction")
  local out = {}
  local bs = c.bagSlots
  out[#out + 1] = ("|cff33ccffBags|r  %s/%s slots used   Gold: %s"):format(
    bs and bs.used or "?", bs and bs.total or "?", Money(c.money))
  local list = ItemList(c.bags, query, prices)
  if #list == 0 then out[#out + 1] = "(nothing matches)" end
  for _, l in ipairs(list) do out[#out + 1] = l end
  local sum = ns.Data.Worth()
  out[#out + 1] = ("\nWorth at AH prices: %s"):format(Money(sum))
  out[#out + 1] = "\n|cff33ccffBank|r  (open your bank once to update)"
  if c.bank then
    for _, l in ipairs(ItemList(c.bank, query, prices)) do out[#out + 1] = l end
    out[#out + 1] = "|cff888888Bank updated " .. ns.Data.Ago(c.bankUpdated) .. "|r"
  else
    out[#out + 1] = "(not seen yet)"
  end
  return table.concat(out, "\n")
end

local function PricesText(query)
  local rows = ns.Data.FindPrices(query)
  local last = AskAHDB.lastScan and AskAHDB.lastScan[ns.Data.CurrentKey()]
  local out = {
    ("|cff33ccffAuction prices|r  %d items   last full scan: %s"):format(#rows, ns.Data.Ago(last)),
    "Type in the search box to filter. /askah scan at the AH to refresh everything.",
    "",
  }
  if #rows == 0 then out[#out + 1] = "No prices yet. Open the auction house and type /askah scan." end
  local LIMIT = 300
  for i = 1, math.min(#rows, LIMIT) do
    local r = rows[i]
    out[#out + 1] = ("%s  |cffffd200%s|r  x%d  |cff888888%s|r"):format(r.n, Money(r.p), r.q or 0, ns.Data.Ago(r.t))
  end
  if #rows > LIMIT then out[#out + 1] = ("...and %d more. Search to narrow it down."):format(#rows - LIMIT) end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local TAB_DEFS = {
  { key = "guide", label = "Guide" },
  { key = "stats", label = "Character" },
  { key = "bags", label = "Bags" },
  { key = "prices", label = "Prices" },
}

local function Create()
  window = CreateFrame("Frame", "AskAHWindow", UIParent, ns.Style.Template())
  window:SetSize(460, 540)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetClampedToScreen(true)
  window:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "AskAHWindow") -- Escape closes it

  ns.Style.Skin(window, "AskAH |cffffffffGuide|r", 34)

  local prev
  for _, def in ipairs(TAB_DEFS) do
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 14, -42) end
    b:SetText(def.label)
    b:SetScript("OnClick", function()
      mode = def.key
      currentTopic = nil
      ns.RefreshWindow()
    end)
    tabs[def.key] = b
    prev = b
  end

  searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
  searchBox:SetSize(300, 20)
  searchBox:SetPoint("TOPLEFT", 20, -70)
  searchBox:SetAutoFocus(false)
  searchBox:HookScript("OnTextChanged", function() ns.RefreshWindow() end)

  local scanBtn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  scanBtn:SetSize(90, 22)
  scanBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
  scanBtn:SetText("Scan AH")
  scanBtn:SetScript("OnClick", function() ns.Data.Scan() end)

  scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -98)
  scroll:SetPoint("BOTTOMRIGHT", -30, 10)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(400, 1)
  scroll:SetScrollChild(scrollChild)

  textLines = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  textLines:SetPoint("TOPLEFT", 4, 0)
  textLines:SetWidth(396)
  textLines:SetJustifyH("LEFT")
  textLines:SetSpacing(2)
end

function ns.RefreshWindow()
  if not window or not window:IsShown() then return end
  local q = strtrim(searchBox:GetText() or ""):lower()
  local text
  if mode == "stats" then text = StatsText()
  elseif mode == "bags" then text = BagsText(q)
  elseif mode == "prices" then text = PricesText(q)
  else text = GuideText(q) end
  textLines:SetText(text)
  scrollChild:SetHeight(textLines:GetStringHeight() + 20)
  for key, b in pairs(tabs) do
    if key == mode then b:LockHighlight() else b:UnlockHighlight() end
  end
end

function ns.ShowWindow(topic, newMode)
  if not window then Create() end
  currentTopic = topic
  if newMode and newMode ~= "" then
    if newMode == "character" then newMode = "stats" end
    mode = newMode
  end
  -- Sit next to the auction house window (modern or classic-style frame).
  local ah = (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame)
          or (AuctionFrame and AuctionFrame:IsShown() and AuctionFrame)
  if ah and (topic or newMode == "guide") then
    window:ClearAllPoints()
    -- next to the AH, or next to the Deals window when that's open there
    local deals = AskAHDealsWindow
    if deals and deals:IsShown() then window:SetPoint("TOPLEFT", deals, "TOPRIGHT", 4, 0)
    else window:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, 0) end
  end
  window:Show()
  ns.RefreshWindow()
end

function ns.HideWindow()
  if window then window:Hide() end
end

function ns.ToggleWindow()
  if window and window:IsShown() then ns.HideWindow() else ns.ShowWindow(nil) end
end

---------------------------------------------------------------------------
-- Minimap button (like AskQuest's): click for a menu of AskAH features.
-- Drag it around the minimap; the spot is saved. /askah minimap on|off
---------------------------------------------------------------------------
local mmButton, menu

local function MMSettings()
  AskAHDB.minimap = AskAHDB.minimap or {}
  local s = AskAHDB.minimap
  if type(s.angle) ~= "number" then s.angle = 160 end
  return s
end

local function MMPlace()
  local a = math.rad(MMSettings().angle)
  local r = math.min(math.max((Minimap:GetWidth() or 140) / 2 + 10, 80), 105)
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local MENU_ITEMS = {
  { "Gold and leveling guide", function() ns.ShowWindow(nil, "guide") end },
  { "My AH sales", function() if ns.Sales then ns.Sales.ShowView("all") end end },
  { "My auctions (up now)", function() if ns.Sales then ns.Sales.ShowView("active") end end },
  { "AH deals window", function() if ns.Deals then ns.Deals.Toggle() end end },
  { "Scan the AH", function() ns.Data.Scan() end },
  { "Character stats", function() ns.Data.SnapshotStats(); ns.ShowWindow(nil, "stats") end },
  { "Bags and bank", function() ns.Data.SnapshotInventory(); ns.ShowWindow(nil, "bags") end },
  { "AH prices", function() ns.ShowWindow(nil, "prices") end },
  { "Bags worth (chat)", function() SlashCmdList.ASKAH("worth") end },
  { "Settings", function() if ns.OpenOptions then ns.OpenOptions() end end },
  { "All commands (chat)", function() SlashCmdList.ASKAH("help") end },
}

local function CreateMenu()
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  menu = CreateFrame("Frame", "AskAHMinimapMenu", UIParent, tmpl)
  menu:SetFrameStrata("DIALOG")
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  if menu.SetBackdrop then
    menu:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    menu:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  end
  local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("AskAH")
  local y, W, H = -28, 190, 20
  for _, item in ipairs(MENU_ITEMS) do
    local b = CreateFrame("Button", nil, menu)
    b:SetSize(W - 12, H)
    b:SetPoint("TOPLEFT", 6, y)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(item[1])
    b:SetScript("OnClick", function() menu:Hide(); item[2]() end)
    y = y - H
  end
  menu:SetSize(W, -y + 10)
  tinsert(UISpecialFrames, "AskAHMinimapMenu")
  -- close when the mouse has been away from it for a moment
  menu:SetScript("OnUpdate", function(self, el)
    if self:IsMouseOver() or (mmButton and mmButton:IsMouseOver()) then self.away = 0
    else
      self.away = (self.away or 0) + el
      if self.away > 1.5 then self:Hide() end
    end
  end)
  menu:Hide()
end

local function ToggleMenu()
  if not menu then CreateMenu() end
  if menu:IsShown() then menu:Hide() return end
  menu:ClearAllPoints()
  local x = mmButton:GetCenter()
  if x and x > (UIParent:GetWidth() or 0) / 2 then
    menu:SetPoint("TOPRIGHT", mmButton, "BOTTOMLEFT", 8, 8)
  else
    menu:SetPoint("TOPLEFT", mmButton, "BOTTOMRIGHT", -8, 8)
  end
  menu.away = 0
  menu:Show()
end

local function MMCreate()
  mmButton = CreateFrame("Button", "AskAHMinimapButton", Minimap)
  mmButton:SetSize(31, 31)
  mmButton:SetFrameStrata("MEDIUM")
  mmButton:SetFrameLevel(8)
  mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mmButton:RegisterForDrag("LeftButton")
  mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = mmButton:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = mmButton:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01") -- gold coin
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = mmButton:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  mmButton:SetScript("OnClick", function(_, which)
    GameTooltip:Hide()
    if which == "RightButton" then if ns.Sales then ns.Sales.Toggle() end
    else ToggleMenu() end
  end)
  mmButton:SetScript("OnDragStart", function(self)
    if menu then menu:Hide() end
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      MMSettings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
      MMPlace()
    end)
  end)
  mmButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
  end)
  mmButton:SetScript("OnEnter", function(self)
    if menu and menu:IsShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("AskAH", 0.2, 0.8, 1)
    GameTooltip:AddLine("Left-click: menu", 1, 1, 1)
    GameTooltip:AddLine("Right-click: my AH sales", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Hide it in Esc > Options > AddOns > AskAH", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
  if not Minimap or not AskAHDB then return end
  if not mmButton then MMCreate() end
  if MMSettings().hide then mmButton:Hide() else MMPlace(); mmButton:Show() end
end

local mmEv = CreateFrame("Frame")
mmEv:RegisterEvent("PLAYER_LOGIN")
mmEv:SetScript("OnEvent", function() pcall(ns.UpdateMinimapButton) end)
-- after a /reload of a newer AskAH, PLAYER_LOGIN still fires; this covers
-- the case where UI.lua loads after login anyway
if IsLoggedIn and IsLoggedIn() then pcall(ns.UpdateMinimapButton) end

---------------------------------------------------------------------------
-- "Gold & leveling guide" button under the auction house window.
---------------------------------------------------------------------------
local ahButton
function ns.AttachAHButton()
  local ah = (AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame)
          or (AuctionFrame and AuctionFrame:IsShown() and AuctionFrame)
  if not ah then return end
  if not ahButton then
    ahButton = CreateFrame("Button", "AskAHGuideButton", UIParent, "UIPanelButtonTemplate")
    ahButton:SetSize(170, 22)
    ahButton:SetText("Gold & leveling guide")
    ahButton:SetFrameStrata("HIGH")
    ahButton:SetScript("OnClick", function()
      if window and window:IsShown() and mode == "guide" then ns.HideWindow()
      else ns.ShowWindow(nil, "guide") end
    end)
  end
  ahButton:ClearAllPoints()
  -- above the top-right corner, so it never covers the tabs along the
  -- bottom (Buy/Sell/Auctions, plus tabs other addons add there)
  ahButton:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", -24, 2)
  ahButton:Show()
end
function ns.DetachAHButton() if ahButton then ahButton:Hide() end end
