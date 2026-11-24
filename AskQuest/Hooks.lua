-- Hooks.lua
-- Shows the reward / worth-it panel:
--  * when you hover a quest in the quest log (panel opens to the right of the log)
--  * when a quest giver offers a quest or you turn one in (panel beside the quest window)
-- Uses only hooksecurefunc and events, and its own tooltip frame (AskQuestTip),
-- so it leaves GameTooltip, Questie and Forever Mouse Tooltip alone.
local _, ns = ...

local function Enabled() return AskQuestDB.info ~= false end

---------------------------------------------------------------------------
-- Quest log (classic-era QuestLogFrame)
---------------------------------------------------------------------------
local function LogIndex(button)
  local offset = (QuestLogListScrollFrame and FauxScrollFrame_GetOffset) and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
  return button:GetID() + offset
end

local function LogQuest(index)
  if not GetQuestLogTitle then return end
  local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
  if isHeader or not title then return end
  return questID, title, level
end

-- Rewards of the selected log entry are readable live: remember them.
local function LearnSelected()
  if not GetQuestLogSelection then return end
  local index = GetQuestLogSelection()
  local id = index and index > 0 and LogQuest(index)
  if id and id > 0 then
    local choices, fixed = ns.LiveRewards("log")
    ns.Learn(id, choices, fixed)
    if GetQuestLogRewardMoney then
      local money = GetQuestLogRewardMoney()
      if money and money > 0 then
        AskQuestDB.gold = AskQuestDB.gold or {}
        AskQuestDB.gold[id] = money
      end
    end
  end
end

local function OnLogEnter(button)
  if not Enabled() then return end
  local id, title, level = LogQuest(LogIndex(button))
  if not id or id == 0 then return end
  local live
  if not ns.quests[id] then live = { title = title, level = level } end
  local anchor = QuestLogFrame and { "TOPLEFT", QuestLogFrame, "TOPRIGHT", -30, -12 } or "ANCHOR_RIGHT"
  ns.ShowQuestTip(id, button, anchor, live)
end

if type(QuestLogTitleButton_OnEnter) == "function" then
  hooksecurefunc("QuestLogTitleButton_OnEnter", OnLogEnter)
end
if type(QuestLogTitleButton_OnLeave) == "function" then
  hooksecurefunc("QuestLogTitleButton_OnLeave", function(button) ns.HideQuestTip(button) end)
end
if type(QuestLog_SetSelection) == "function" then
  hooksecurefunc("QuestLog_SetSelection", function() pcall(LearnSelected) end)
end
-- Newer quest log (in case the client uses the map-side log)
if type(QuestMapLogTitleButton_OnEnter) == "function" then
  hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(button)
    if Enabled() and button and button.questID then ns.ShowQuestTip(button.questID, button, "ANCHOR_RIGHT") end
  end)
  if type(QuestMapLogTitleButton_OnLeave) == "function" then
    hooksecurefunc("QuestMapLogTitleButton_OnLeave", function(button) ns.HideQuestTip(button) end)
  end
end

---------------------------------------------------------------------------
-- Quest giver window: offer (QUEST_DETAIL) and turn-in (QUEST_COMPLETE)
---------------------------------------------------------------------------
local function LiveFromGiver()
  local id = GetQuestID and GetQuestID()
  if not id or id == 0 then return end
  local choices, fixed = ns.LiveRewards("quest")
  ns.Learn(id, choices, fixed)
  local live = {
    choices = choices, fixed = fixed,
    money = GetRewardMoney and GetRewardMoney() or nil,
    xp = GetRewardXP and GetRewardXP() or nil,
    title = GetTitleText and GetTitleText() or nil,
  }
  return id, live
end

local holder = QuestFrame or UIParent

local function ShowAtGiver()
  if not Enabled() then return end
  local id, live = LiveFromGiver()
  if not id then return end
  local anchor = QuestFrame and { "TOPLEFT", QuestFrame, "TOPRIGHT", -30, -14 } or "ANCHOR_CURSOR"
  ns.ShowQuestTip(id, holder, anchor, live)
end

-- Every quest in your log has its rewards readable from the game, without
-- opening it: select each entry in turn (quietly), read, then put the
-- selection back. Fills in rewards the Blizzard API data doesn't have.
local scanning, lastScan = false, 0
local function LearnWholeLog()
  if scanning or not (GetNumQuestLogEntries and SelectQuestLogEntry and GetQuestLogSelection) then return end
  if QuestLogFrame and QuestLogFrame:IsShown() then return end -- don't move your selection under you
  scanning = true
  local keep = GetQuestLogSelection()
  local pending = false
  for i = 1, (GetNumQuestLogEntries() or 0) do
    local id = LogQuest(i)
    if id and id > 0 then
      SelectQuestLogEntry(i)
      local nc = GetNumQuestLogChoices and GetNumQuestLogChoices() or 0
      local nr = GetNumQuestLogRewards and GetNumQuestLogRewards() or 0
      local choices, fixed = ns.LiveRewards("log")
      if #choices < nc or #fixed < nr then pending = true -- item not cached yet; next pass
      elseif nc + nr == 0 then
        AskQuestDB.noItems = AskQuestDB.noItems or {}
        AskQuestDB.noItems[id] = true
      else ns.Learn(id, choices, fixed) end
      local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney()
      if money and money > 0 then AskQuestDB.gold = AskQuestDB.gold or {}; AskQuestDB.gold[id] = money end
    end
  end
  SelectQuestLogEntry(keep or 0)
  scanning = false
  lastScan = GetTime and GetTime() or 0
  if pending and C_Timer and C_Timer.After then C_Timer.After(3, function() pcall(LearnWholeLog) end) end
end
ns.LearnWholeLog = LearnWholeLog

local logEv = CreateFrame("Frame")
logEv:RegisterEvent("PLAYER_ENTERING_WORLD")
logEv:RegisterEvent("QUEST_ACCEPTED")
logEv:SetScript("OnEvent", function()
  if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(LearnWholeLog) end) end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("QUEST_FINISHED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:SetScript("OnEvent", function(_, event)
  if event == "QUEST_FINISHED" then ns.HideQuestTip(holder) return end
  if event == "QUEST_LOG_UPDATE" then
    if scanning then return end
    if QuestLogFrame and QuestLogFrame:IsShown() then pcall(LearnSelected) end
    return
  end
  -- Wait one frame so the reward buttons are filled in.
  if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(ShowAtGiver) end)
  else pcall(ShowAtGiver) end
end)

if QuestFrame then
  QuestFrame:HookScript("OnHide", function() ns.HideQuestTip(holder) end)
end
if QuestLogFrame then
  QuestLogFrame:HookScript("OnHide", function() ns.HideQuestTip() end)
end
