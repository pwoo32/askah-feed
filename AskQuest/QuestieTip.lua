-- QuestieTip.lua
-- Hold Shift over a Questie quest icon (world map or minimap) and the tooltip
-- also lists every quest's rewards: XP, gold, each item with AskQuest's
-- verdict (upgrade, can't use, what it sells for) and the worth-it rating.
--
-- How it hooks (Questie 12.x): MapIconTooltip.ShowOnTooltip builds the
-- tooltip and stores its row builder as tooltip._Rebuild, which Questie calls
-- again when Shift is pressed or released. We post-hook ShowOnTooltip and wrap
-- that fresh _Rebuild so our lines follow Questie's every time. Nothing of
-- Questie is replaced, and without Questie this file does nothing.
local _, ns = ...

local MAX_QUESTS = 8
local HEADER = "|cff33ccffAskQuest rewards|r"

local function Enabled() return AskQuestDB and AskQuestDB.questieRewards ~= false end

-- Quest IDs the tooltip lists: givers' quests first (as Questie sorts them), then active ones.
local function QuestIDs(tooltip)
  local ids, seen = {}, {}
  local function put(id)
    if type(id) == "number" and id > 0 and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  local givers = {}
  for name in pairs(tooltip.npcAndObjectOrder or {}) do givers[#givers + 1] = name end
  table.sort(givers)
  for _, name in ipairs(givers) do
    local list = {}
    for _, qd in pairs(tooltip.npcAndObjectOrder[name]) do if type(qd) == "table" then list[#list + 1] = qd.questId end end
    table.sort(list)
    for _, id in ipairs(list) do put(id) end
  end
  local active = {}
  for id in pairs(tooltip.questOrder or {}) do active[#active + 1] = id end
  table.sort(active)
  for _, id in ipairs(active) do put(id) end
  return ids
end

local waiting = {} -- tooltips whose item info is still loading

local function AddRewards(tooltip)
  if not (Enabled() and IsShiftKeyDown() and ns.RewardSummary) then return end
  local ids = QuestIDs(tooltip)
  if #ids == 0 then return end
  tooltip:AddLine(" ")
  tooltip:AddLine(HEADER)
  local loading = false
  for i, id in ipairs(ids) do
    if i > MAX_QUESTS then
      tooltip:AddLine(("|cff999999...and %d more quests here (hover closer)|r"):format(#ids - MAX_QUESTS))
      break
    end
    local ok, lines, load = pcall(ns.RewardSummary, id)
    if ok and lines then
      loading = loading or load
      for _, l in ipairs(lines) do
        if l[2] then tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
        else tooltip:AddLine(l[1], 1, 1, 1) end
      end
    end
  end
  waiting[tooltip] = loading or nil
end

local function Wrap(tooltip)
  local rebuild = tooltip and tooltip._Rebuild
  -- Questie returned early (faded icon, throttle): the old builder is still ours.
  if type(rebuild) ~= "function" or tooltip._askQuestRebuild == rebuild then return end
  local wrapped = function(self, ...)
    rebuild(self, ...)
    pcall(AddRewards, self)
  end
  tooltip._Rebuild, tooltip._askQuestRebuild = wrapped, wrapped
  -- ShowOnTooltip already built and showed it once: add ours and resize.
  pcall(AddRewards, tooltip)
  tooltip:Show()
end

local hooked = false
local function Hook()
  if hooked or not (QuestieLoader and QuestieLoader.ImportModule) then return end
  local ok, MapIconTooltip = pcall(QuestieLoader.ImportModule, QuestieLoader, "MapIconTooltip")
  if not ok or type(MapIconTooltip) ~= "table" or type(MapIconTooltip.ShowOnTooltip) ~= "function" then return end
  hooksecurefunc(MapIconTooltip, "ShowOnTooltip", function(_, tooltip)
    pcall(Wrap, tooltip)
  end)
  hooked = true
end

Hook()
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local pending = false
ev:SetScript("OnEvent", function(_, event)
  if event ~= "GET_ITEM_INFO_RECEIVED" then Hook(); return end
  -- An item finished loading: redraw an open Questie tooltip that was waiting on it.
  if pending or not next(waiting) then return end
  pending = true
  C_Timer.After(0.2, function()
    pending = false
    for tooltip in pairs(waiting) do
      waiting[tooltip] = nil
      if tooltip:IsShown() and tooltip.ShownAsMapIcon and tooltip._Rebuild == tooltip._askQuestRebuild and IsShiftKeyDown() then
        local owner = tooltip:GetOwner()
        tooltip:ClearLines()
        tooltip:SetOwner(owner or UIParent, "ANCHOR_CURSOR")
        tooltip:_Rebuild()
        tooltip:Show()
      end
    end
  end)
end)
