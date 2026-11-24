-- Blizz.lua
-- Blizzard's own quest data for WoW: Forever (BlizzQuests.lua, written by
-- AskAH\Feed\AskStatic.ps1): gold, XP and reward items for every quest,
-- including the Forever-new ones that used to show "? gold". This data comes
-- first; gold and rewards seen in game are the fallback, then the bundled
-- QuestieDB/cMaNGOS data.
local _, ns = ...
local XP, GOLD = 5, 6

-- Remember which quests are new in Forever before the gold gets filled in.
ns.isNew = {}
for id, q in pairs(ns.quests) do
  if q[GOLD] == -1 then ns.isNew[id] = true end
end
function ns.IsNew(id) return ns.isNew[id] == true end

ns.blizzCount = 0
ns.blizzGold, ns.blizzRewards = {}, {}
local B = type(AskQuestBlizz) == "table" and AskQuestBlizz.quests
if B then
  for id, s in pairs(B) do
    local q = ns.quests[id] or {}
    if s ~= "" then
      local xp, money, choice, fixed = s:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)")
      xp, money = tonumber(xp), tonumber(money)
      if money then q[GOLD] = money; ns.blizzGold[id] = money end
      if xp and xp > 0 then q[XP] = xp end
      local c, f = {}, {}
      for x in (choice or ""):gmatch("%d+") do c[#c + 1] = tonumber(x) end
      for x in (fixed or ""):gmatch("%d+") do f[#f + 1] = tonumber(x) end
      -- kept apart from the bundled cMaNGOS rewards, which stay as a fallback
      ns.blizzRewards[id] = { c, f }
      ns.blizzCount = ns.blizzCount + 1
    end
  end
end
