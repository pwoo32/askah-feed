-- UI.lua
-- Window with a quest chart: ask a question (or click a quick button), then
-- read the results as a table. Click a column header to sort by it; click again
-- to flip the order. XP and gold have bars so the big rewards stand out.
-- Hover a row for rewards and the worth-it verdict. Click a row for the full
-- details panel (rewards, chain, why) with buttons that pin the quest giver on
-- your map. Right-click a row to pin the giver right away; shift-click puts the
-- quest name in chat.
local _, ns = ...
local F = ns.F

local ROWS, ROW_H = 18, 20
local window, box, summary, pageText
local rows, headers = {}, {}
local results, offset = {}, 0
local sortCol, sortDesc

local COLS = {
  { key = "rank", label = "#", width = 28, align = "RIGHT" },
  { key = "value", label = "Value", width = 84, align = "LEFT", bar = { 0.7, 0.4, 1.0 } },
  { key = "name", label = "Quest", width = 165, align = "LEFT" },
  { key = "lvl", label = "Lvl", width = 30, align = "CENTER" },
  { key = "zone", label = "Zone", width = 95, align = "LEFT" },
  { key = "giver", label = "Quest giver (x, y)", width = 160, align = "LEFT" },
  { key = "xp", label = "XP", width = 80, align = "RIGHT", bar = { 0.2, 0.6, 1.0 } },
  { key = "gold", label = "Gold + items", width = 102, align = "RIGHT", bar = { 1.0, 0.82, 0.0 } },
  { key = "pop", label = "Pop", width = 36, align = "RIGHT", bar = { 0.3, 0.9, 0.4 } },
  { key = "type", label = "Type", width = 50, align = "LEFT" },
  { key = "why", label = "Why it's good for you", width = 185, align = "LEFT" },
}

local QUICK = {
  { "Best here", "best quest here" },
  { "Most XP here", "most xp here" },
  { "Most gold here", "most gold here" },
  { "Popular here", "most popular here" },
  { "Most XP anywhere", "most xp anywhere" },
  { "Most gold anywhere", "most gold anywhere" },
  { "Popular anywhere", "most popular anywhere" },
  { "Best for me", "best quests for me anywhere" },
}

-- Rank = place in the answer (1 = most valuable for "best for me").
local rankOf = {}
local TIER = { great = { "|cff33ff33", "Great" }, worth = { "|cff33ff33", "Worth it" }, ok = { "|cffffd200", "OK" },
               skip = { "|cffff4040", "Skip" }, later = { "|cffff8040", "Not yet" },
               important = { "|cffa335ee", "Important" } }

-- WhyShort is worked out once per question (it checks items against your gear).
local whyCache = {}
local function Why(id)
  local c = whyCache[id]
  if not c then
    local ok, text, a = pcall(ns.WhyShort, id)
    c = ok and { text, a.score, a.loading, a.tierKey } or { "", 0 }
    if not (ok and a.loading) then whyCache[id] = c end
  end
  return c
end
ns.ClearWhyCache = function() whyCache = {} end

local function Value(id, key)
  local q = ns.quests[id]
  if key == "why" or key == "value" then return Why(id)[2] end
  if key == "rank" then return rankOf[id] or 0 end
  if key == "giver" then return q[F.GIVER] > 0 and ns.givers[q[F.GIVER]] or "~" end
  if key == "name" then return q[F.NAME] end
  if key == "lvl" then return q[F.LVL] end
  if key == "zone" then return ns.zones[q[F.ZONE]] end
  if key == "xp" then return q[F.XP] end
  if key == "gold" then return ns.TotalGold and ns.TotalGold(id, q) or ns.Gold(id, q) end
  if key == "pop" then return q[F.POP] end
  if key == "type" then
    if q[F.KIND] ~= 2 and ns.DungeonImportant and ns.DungeonImportant(id) then return "Lead-in" end
    return ns.KIND_TEXT[q[F.KIND]] or "Solo"
  end
end

local function Cell(id, key)
  local q = ns.quests[id]
  if key == "lvl" then
    local color = (q[F.REQ] > (UnitLevel("player") or 1)) and "|cffff4040" or ""
    return color .. q[F.LVL] .. (color ~= "" and "|r" or "")
  end
  if key == "xp" then return ns.Commas(q[F.XP]) end
  if key == "gold" then
    local g = ns.Gold(id, q)
    local items, r = 0, nil
    if ns.RewardGold then items, r = ns.RewardGold(id) end
    if not items or items <= 0 then return ns.Money(g) end
    -- reward items: where to sell the best one (A = AH, V = vendor)
    local tag = (r and (r.where == "faction" or r.where == "neutral")) and "AH" or "V"
    return ((g and g > 0) and (ns.Money(g) .. " ") or "") .. "|cff999999+|r" .. ns.Money(items) .. " |cff999999" .. tag .. "|r"
  end
  if key == "name" then
    local lead = ns.DungeonImportant and ns.DungeonImportant(id)
    return (lead and "|cffa335ee! |r" or "") .. q[F.NAME] .. (ns.IsNew(id) and " |cffff8040(new)|r" or "")
  end
  if key == "why" then return "|cffcccccc" .. Why(id)[1] .. "|r" end
  if key == "rank" then return "|cffffd200" .. (rankOf[id] or "") .. "|r" end
  if key == "value" then
    local w = Why(id)
    local t = TIER[w[4] or ""] or TIER.skip
    return ("%s%.1f %s|r"):format(t[1], w[2] or 0, t[2])
  end
  if key == "giver" then
    if q[F.GIVER] == 0 then return "|cff999999item / object|r" end
    local xy = q[F.GX] > 0 and ("|cff999999 (%.0f, %.0f)|r"):format(q[F.GX], q[F.GY]) or ""
    return ns.givers[q[F.GIVER]] .. xy
  end
  return tostring(Value(id, key) or "")
end

local maxOf = {}

local function Redraw()
  if not window then return end
  for _, key in ipairs({ "xp", "gold", "pop", "value" }) do
    local m = 1
    for _, id in ipairs(results) do
      local v = Value(id, key) or 0
      if v > m then m = v end
    end
    maxOf[key] = m
  end
  for i = 1, ROWS do
    local row, id = rows[i], results[offset + i]
    if id then
      row.id = id
      for c, col in ipairs(COLS) do
        row.cells[c]:SetText(Cell(id, col.key))
        if row.bars[c] then
          local v = math.max(Value(id, col.key) or 0, 0)
          local w = math.max(1, (col.width - 6) * v / maxOf[col.key])
          row.bars[c]:SetWidth(w)
          row.bars[c]:SetShown(v > 0)
        end
      end
      row:Show()
    else
      row.id = nil
      row:Hide()
    end
  end
  local last = math.min(offset + ROWS, #results)
  pageText:SetText(#results == 0 and "No quests" or ("%d-%d of %d  (mouse wheel to scroll)"):format(offset + 1, last, #results))
  for c, col in ipairs(COLS) do
    local arrow = (sortCol == col.key) and (sortDesc and " v" or " ^") or ""
    headers[c]:SetText(col.label .. arrow)
  end
end

local function Scroll(delta)
  local maxOff = math.max(0, #results - ROWS)
  offset = math.min(maxOff, math.max(0, offset - delta * 3))
  Redraw()
end

local function SortBy(key)
  if sortCol == key then sortDesc = not sortDesc
  else sortCol, sortDesc = key, not (key == "name" or key == "zone" or key == "type" or key == "giver" or key == "rank") end
  table.sort(results, function(a, b)
    local va, vb = Value(a, key), Value(b, key)
    if va == vb then return ns.quests[a][F.XP] > ns.quests[b][F.XP] end
    if sortDesc then return va > vb end
    return va < vb
  end)
  offset = 0
  Redraw()
end

local function Run(question)
  if not window then return end
  local _, res, _, header = ns.Answer(question or "")
  results = res or {}
  whyCache, rankOf = {}, {}
  for i, id in ipairs(results) do rankOf[id] = i end
  sortCol, sortDesc, offset = nil, nil, 0
  summary:SetText(header or "")
  Redraw()
end

local function RowTooltip(row)
  if not row.id then return end
  -- Open to the left of the chart so it never covers the details panel.
  ns.ShowQuestTip(row.id, row, { "TOPRIGHT", window, "TOPLEFT", -2, 0 })
end

---------------------------------------------------------------------------
-- Details panel (opens to the right of the chart when you click a quest)
---------------------------------------------------------------------------
local details, detailsText, detailsChild, giverBtn, enderBtn, startBtn
local detailsID

-- Live progress from your quest log ("Bluegill Murloc slain: 5/12"), if you have the quest.
local function LogProgress(id)
  if not (GetNumQuestLogEntries and GetQuestLogTitle and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard) then return nil end
  for i = 1, (GetNumQuestLogEntries() or 0) do
    local _, _, _, isHeader, _, _, _, qid = GetQuestLogTitle(i)
    if not isHeader and qid == id then
      local out = {}
      for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
        local text, _, done = GetQuestLogLeaderBoard(j, i)
        if text then out[#out + 1] = { text, done } end
      end
      return out
    end
  end
end

-- Every step of a quest: pick up, objectives (how many, where, what drops it), turn in.
function ns.StepLines(id, indent, short)
  indent = indent or ""
  local q = ns.quests[id]
  local out = {}
  local steps = ns.steps and ns.steps[id] or {}
  local n = 0
  local function add(t) n = n + 1; out[#out + 1] = ("%s%d. %s"):format(indent, n, t) end
  if q and q[F.GIVER] > 0 and not short then
    local where = ns.Where and ns.Where(q[F.GMAP], q[F.GX], q[F.GY], ns.zones[q[F.ZONE]]) or ns.zones[q[F.ZONE]]
    add("Get the quest from |cffffd200" .. ns.givers[q[F.GIVER]] .. "|r, " .. where)
  end
  local progress = LogProgress(id)
  local objText
  for _, l in ipairs(steps) do
    if l:sub(1, 1) == "#" then objText = l:sub(2)
    else add(l) end
  end
  if progress and #progress > 0 then
    for _, p in ipairs(progress) do
      out[#out + 1] = indent .. "    " .. (p[2] and "|cff33ff33" or "|cffffd200") .. p[1] .. (p[2] and " (done)" or "") .. "|r"
    end
  end
  if q and q[F.ENDER] > 0 then
    if short then add("Turn in to " .. ns.givers[q[F.ENDER]])
    else
      local where = ns.Where and ns.Where(q[F.EMAP], q[F.EX], q[F.EY], ns.zones[q[F.ZONE]]) or ""
      add("Turn in to |cffffd200" .. ns.givers[q[F.ENDER]] .. "|r, " .. where)
    end
  end
  if objText and (not short or n <= 1) then table.insert(out, 1, indent .. "|cffccccccObjective: " .. objText .. "|r") end
  return out
end

local function DetailsBody(id)
  local out = {}
  local lines = ns.QuestReport(id)
  for _, l in ipairs(lines) do
    out[#out + 1] = l[2] and ("|cffffd200" .. l[1] .. ":|r  " .. l[2]) or l[1]
  end
  out[#out + 1] = " "
  out[#out + 1] = "|cff33ccffQuest steps|r"
  for _, l in ipairs(ns.StepLines(id, "  ")) do out[#out + 1] = l end
  local chain = ns.ChainLines and ns.ChainLines(id)
  if chain then
    out[#out + 1] = " "
    for _, l in ipairs(chain) do out[#out + 1] = l end
  end
  local q = ns.quests[id]
  out[#out + 1] = " "
  out[#out + 1] = ("|cff999999Popularity ~%d/100 (estimate). Quest ID %d.|r"):format(q[F.POP], id)
  if ns.IsNew(id) then out[#out + 1] = "|cff999999New in Forever.|r" end
  return table.concat(out, "\n")
end

local function RefreshDetails()
  if not details or not detailsID or not details:IsShown() then return end
  local q = ns.quests[detailsID]
  details.title:SetText(q[F.NAME])
  detailsText:SetText(DetailsBody(detailsID))
  detailsChild:SetHeight(detailsText:GetStringHeight() + 10)
  giverBtn:SetEnabled(q[F.GIVER] > 0)
  local ender = q[F.ENDER] > 0 and q[F.ENDER] ~= q[F.GIVER]
  enderBtn:SetShown(ender)
  local first, here = ns.ChainStart(detailsID)
  startBtn:SetShown(first ~= nil and here > 1)
end
ns.RefreshDetails = RefreshDetails

local function CreateDetails()
  details = CreateFrame("Frame", "AskQuestDetails", window, ns.WindowTemplate())
  details:SetSize(400, window:GetHeight())
  details:SetPoint("TOPLEFT", window, "TOPRIGHT", 2, 0)
  details:EnableMouse(true)
  details.title = ns.Skin(details, "", 34)

  local scroll = CreateFrame("ScrollFrame", "AskQuestDetailsScroll", details, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -40)
  scroll:SetPoint("BOTTOMRIGHT", -30, 72)
  detailsChild = CreateFrame("Frame", nil, scroll)
  detailsChild:SetSize(350, 10)
  scroll:SetScrollChild(detailsChild)
  detailsText = detailsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detailsText:SetPoint("TOPLEFT", 2, -2)
  detailsText:SetWidth(346)
  detailsText:SetJustifyH("LEFT")
  detailsText:SetSpacing(2)

  giverBtn = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
  giverBtn:SetSize(150, 24)
  giverBtn:SetPoint("BOTTOMLEFT", 14, 12)
  giverBtn:SetText("Show quest giver")
  giverBtn:SetScript("OnClick", function() if detailsID then ns.PointTo(detailsID, "giver") end end)

  enderBtn = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
  enderBtn:SetSize(120, 24)
  enderBtn:SetPoint("LEFT", giverBtn, "RIGHT", 6, 0)
  enderBtn:SetText("Show turn-in")
  enderBtn:SetScript("OnClick", function() if detailsID then ns.PointTo(detailsID, "ender") end end)

  startBtn = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
  startBtn:SetSize(150, 24)
  startBtn:SetPoint("BOTTOMLEFT", giverBtn, "TOPLEFT", 0, 4)
  startBtn:SetText("Show chain start")
  startBtn:SetScript("OnClick", function()
    local first = detailsID and ns.ChainStart(detailsID)
    if first then ns.PointTo(first, "giver") end
  end)

  local link = CreateFrame("Button", nil, details, "UIPanelButtonTemplate")
  link:SetSize(80, 24)
  link:SetPoint("BOTTOMRIGHT", -14, 12)
  link:SetText("To chat")
  link:SetScript("OnClick", function()
    if detailsID and ChatEdit_InsertLink then ChatEdit_InsertLink("[" .. ns.quests[detailsID][F.NAME] .. "]") end
  end)
end

function ns.ShowDetails(id)
  if not window then return end
  if not details then CreateDetails() end
  detailsID = id
  details:Show()
  RefreshDetails()
end

-- Item info arrives a moment later the first time: refresh what's on screen.
local itemEv = CreateFrame("Frame")
itemEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
local function RefreshAll()
  pending = false
  if details and details:IsShown() then RefreshDetails() end
  if window and window:IsShown() then Redraw() end
end
itemEv:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  if C_Timer and C_Timer.After then C_Timer.After(0.3, RefreshAll) else RefreshAll() end
end)

---------------------------------------------------------------------------
-- Point at the quest giver: map pin + arrow on the minimap, TomTom if you have it
---------------------------------------------------------------------------
function ns.PointTo(id, which)
  local q = ns.quests[id]
  if not q then return end
  local npc, map, x, y
  if which == "ender" then npc, map, x, y = q[F.ENDER], q[F.EMAP], q[F.EX], q[F.EY]
  else npc, map, x, y = q[F.GIVER], q[F.GMAP], q[F.GX], q[F.GY] end
  local who = npc > 0 and ns.givers[npc] or "the quest giver"
  local zone = ns.zones[q[F.ZONE]]
  if not map or map == 0 or not x or x <= 0 then
    ns.Print(("%s for %s: no map spot known (%s). Questie's map icons will show it."):format(who, q[F.NAME], zone))
    return
  end
  local pinned = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then error("no") end
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    pinned = ok
  end
  if TomTom and TomTom.AddWaypoint then
    pcall(TomTom.AddWaypoint, TomTom, map, x / 100, y / 100, { title = who .. " (" .. q[F.NAME] .. ")", from = "AskQuest" })
    pinned = true
  end
  if WorldMapFrame and not InCombatLockdown() then
    pcall(function()
      if not WorldMapFrame:IsShown() then
        if OpenWorldMap then OpenWorldMap(map) elseif ToggleWorldMap then ToggleWorldMap() end
      end
      if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(map) end
    end)
  end
  ns.Print(("go to |cffffd200%s|r in %s at %.1f, %.1f%s"):format(who, zone, x, y,
    pinned and " - pinned on your map and minimap." or "."))
end

local function Create()
  local totalW = 0
  for _, col in ipairs(COLS) do totalW = totalW + col.width end

  window = CreateFrame("Frame", "AskQuestWindow", UIParent, ns.WindowTemplate())
  window:SetSize(totalW + 40, 160 + ROWS * ROW_H + 30)
  window:SetPoint("CENTER")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetClampedToScreen(true)
  window:SetFrameStrata("HIGH")
  window:EnableMouseWheel(true)
  window:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
  tinsert(UISpecialFrames, "AskQuestWindow")

  ns.Skin(window, "AskQuest |cffffffffQuest chart|r", 34)

  box = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
  box:SetSize(totalW - 90, 22)
  box:SetPoint("TOPLEFT", 24, -42)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function(self) Run(self:GetText()) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local ask = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  ask:SetSize(70, 22)
  ask:SetPoint("LEFT", box, "RIGHT", 8, 0)
  ask:SetText("Ask")
  ask:SetScript("OnClick", function() Run(box:GetText()) end)

  local prev
  for _, def in ipairs(QUICK) do
    local b = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    b:SetSize(math.floor((totalW - 4 * (#QUICK - 1)) / #QUICK), 22)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -70) end
    b:SetText(def[1])
    b:SetScript("OnClick", function() box:SetText(def[2]) Run(def[2]) end)
    prev = b
  end

  summary = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  summary:SetPoint("TOPLEFT", 18, -102)
  summary:SetWidth(totalW)
  summary:SetJustifyH("LEFT")

  -- Column headers (click to sort)
  local x = 18
  for c, col in ipairs(COLS) do
    local h = CreateFrame("Button", nil, window)
    h:SetSize(col.width, 20)
    h:SetPoint("TOPLEFT", x, -122)
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints()
    fs:SetJustifyH(col.align)
    h:SetFontString(fs)
    h:SetText(col.label)
    h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    h:SetScript("OnClick", function() SortBy(col.key) end)
    headers[c] = h
    x = x + col.width
  end

  -- Rows
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, window)
    row:SetSize(totalW, ROW_H)
    row:SetPoint("TOPLEFT", 18, -142 - (i - 1) * ROW_H)
    if i % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.cells, row.bars = {}, {}
    local cx = 0
    for c, col in ipairs(COLS) do
      if col.bar then
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("RIGHT", row, "LEFT", cx + col.width - 3, 0)
        bar:SetHeight(ROW_H - 6)
        bar:SetColorTexture(col.bar[1], col.bar[2], col.bar[3], 0.25)
        row.bars[c] = bar
      end
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", cx + 3, 0)
      fs:SetSize(col.width - 6, ROW_H)
      fs:SetJustifyH(col.align)
      fs:SetWordWrap(false)
      row.cells[c] = fs
      cx = cx + col.width
    end
    row.isAskQuestRow = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function(self) ns.HideQuestTip(self) end)
    row:SetScript("OnClick", function(self, button)
      if not self.id then return end
      if IsShiftKeyDown() and ChatEdit_InsertLink then
        ChatEdit_InsertLink("[" .. ns.quests[self.id][F.NAME] .. "]")
      elseif button == "RightButton" then
        ns.PointTo(self.id, "giver")
      else
        ns.ShowDetails(self.id)
      end
    end)
    rows[i] = row
  end

  pageText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pageText:SetPoint("BOTTOMLEFT", 18, 12)
  local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -18, 12)
  hint:SetText("Click a quest for details. Right-click: show the giver on your map. Red level = can't take it yet.")
end

function ns.ToggleWindow()
  if not window then Create() end
  if window:IsShown() then window:Hide() return end
  window:Show()
  if (box:GetText() or "") == "" then box:SetText("best quest here") end
  Run(box:GetText())
end

-- Re-run the current question (after you turn in a quest, done ones drop off).
function ns.RefreshWindow()
  if window and window:IsShown() then Run(box:GetText()) end
  if ns.RefreshDetails then ns.RefreshDetails() end
end

function ns.ShowInWindow(question)
  if not window then Create() end
  window:Show()
  box:SetText(question)
  Run(question)
end
