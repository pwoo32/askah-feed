-- Chain.lua
-- Quest chains: every step of the chain a quest belongs to, what the whole
-- chain gives you, how popular it is, and whether to do it or skip it.
local _, ns = ...
local F = ns.F
local GREEN, RED, YELLOW, GREY, BLUE = "|cff33ff33", "|cffff4040", "|cffffd200", "|cff999999", "|cff33ccff"

local StartLines
local prev -- built on first use: [questID] = previous quest
local function Prev()
  if prev then return prev end
  prev = {}
  for a, b in pairs(ns.chainNext or {}) do prev[b] = a end
  return prev
end

---------------------------------------------------------------------------
-- Chains that lead into a dungeon quest
---------------------------------------------------------------------------
-- Follows the chain forward (QuestieDB "next quest in chain" data baked into
-- QuestData.lua, plus Questie's breadcrumb links when Questie is installed)
-- and returns the first dungeon quest it reaches, or nil.
local leadCache = {}
function ns.DungeonLead(id)
  local c = leadCache[id]
  if c ~= nil then return c or nil end
  local q = ns.quests[id]
  local found = false
  if q and q[F.KIND] ~= 2 then
    local cur, seen = id, { [id] = true }
    for _ = 1, 40 do
      local nxt = ns.chainNext and ns.chainNext[cur]
      if not nxt and ns.QuestieField then
        local b = ns.QuestieField(cur, "breadcrumbForQuestId")
        if type(b) == "number" and b > 0 then nxt = b end
      end
      if not nxt or seen[nxt] then break end
      seen[nxt] = true
      local nq = ns.quests[nxt]
      if nq and nq[F.KIND] == 2 then found = nxt; break end
      cur = nxt
    end
  end
  -- Before Questie has loaded, a "no" may change later, so only keep it once Questie is up (or absent for good).
  if found or not (ns.HasQuestie and not ns.HasQuestie() and QuestieLoader) then leadCache[id] = found end
  return found or nil
end

-- "The Defias Brotherhood (The Deadmines)"
function ns.DungeonName(did)
  local dq = ns.quests[did]
  if not dq then return "a dungeon quest" end
  local z = ns.dungeonZones and ns.dungeonZones[dq[F.ZONE]] and ns.zones[dq[F.ZONE]]
  return dq[F.NAME] .. (z and (" (" .. z .. ")") or " (dungeon)")
end

-- Short: "The Deadmines" (or the quest's name when it isn't inside a dungeon zone)
function ns.DungeonWhere(did)
  local dq = ns.quests[did]
  if not dq then return "a dungeon" end
  return ns.dungeonZones and ns.dungeonZones[dq[F.ZONE]] and ns.zones[dq[F.ZONE]] or dq[F.NAME]
end

-- Important = leads to a dungeon quest you haven't done that still gives you XP.
function ns.DungeonImportant(id, level)
  local did = ns.DungeonLead(id)
  if not did then return nil end
  level = level or UnitLevel("player") or 1
  local dq = ns.quests[did]
  if dq[F.LVL] < level - 5 then return nil end
  if ns.IsDone and ns.IsDone(did) then return nil end
  return did
end

-- Ordered list of quest IDs in the chain, and this quest's step number.
function ns.ChainSteps(id)
  local p = Prev()
  if not (ns.chainNext and (ns.chainNext[id] or p[id])) then return nil end
  local start, seen = id, { [id] = true }
  while p[start] and not seen[p[start]] do start = p[start]; seen[start] = true end
  local steps, here, cur, guard = {}, 1, start, {}
  while cur and not guard[cur] and #steps < 40 do
    guard[cur] = true
    if ns.quests[cur] then
      steps[#steps + 1] = cur
      if cur == id then here = #steps end
    end
    cur = ns.chainNext[cur]
  end
  if #steps < 2 then return nil end
  return steps, here
end

-- Everything about a chain for you.
function ns.ChainReport(id)
  local steps, here = ns.ChainSteps(id)
  if not steps then return nil end
  local level = UnitLevel("player") or 1
  local c = { steps = steps, here = here, xp = 0, pct = 0, copper = 0, pop = 0,
              zones = {}, nZones = 0, group = 0, upgrades = {}, minL = 999, maxL = 0, maxReq = 0, done = 0 }
  for _, sid in ipairs(steps) do
    local q = ns.quests[sid]
    local a = ns.Assess(sid)
    c.xp, c.pct, c.copper = c.xp + a.xp, c.pct + a.pct, c.copper + a.copper
    c.pop = c.pop + q[F.POP]
    if not c.zones[q[F.ZONE]] then c.zones[q[F.ZONE]] = true; c.nZones = c.nZones + 1 end
    if q[F.KIND] > 0 then c.group = c.group + 1 end
    if a.bestUpgrade then c.upgrades[#c.upgrades + 1] = a.evals[a.bestUpgrade].info.name end
    if a.fixedUpgrade then c.upgrades[#c.upgrades + 1] = a.fixedUpgrade.info.name end
    c.minL, c.maxL = math.min(c.minL, q[F.LVL]), math.max(c.maxL, q[F.LVL])
    c.maxReq = math.max(c.maxReq, q[F.REQ])
    if ns.IsDone(sid) then c.done = c.done + 1 end
    c.last = a
  end
  local n = #steps
  c.pop = math.floor(c.pop / n + 0.5)
  -- first dungeon quest in the chain (only counts if there are steps before it)
  for i, sid in ipairs(steps) do
    if ns.quests[sid][F.KIND] == 2 then
      if i > 1 and ns.quests[sid][F.LVL] >= level - 5 then c.dungeon = sid end
      break
    end
  end

  -- Do it or skip it, in plain words.
  local good, bad = {}, {}
  if c.pct >= 50 then good[#good + 1] = ("%.0f%% of a level in total"):format(c.pct)
  elseif c.pct >= 15 then good[#good + 1] = ("%.0f%% of a level in total"):format(c.pct)
  else bad[#bad + 1] = ("only %.0f%% of a level in total"):format(c.pct) end
  local lastUp = c.last.bestUpgrade and c.last.evals[c.last.bestUpgrade]
  if lastUp then good[#good + 1] = ("final reward %s is an upgrade (+%d%%)"):format(lastUp.info.name, lastUp.gain)
  elseif #c.upgrades > 0 then good[#good + 1] = "upgrade along the way: " .. c.upgrades[1] end
  if c.copper >= level * level * 25 then good[#good + 1] = ns.Money(c.copper) .. " total value" end
  if c.dungeon then good[#good + 1] = "leads to dungeon quest " .. ns.DungeonName(c.dungeon) end
  if c.pop >= 60 then good[#good + 1] = "lots of players do it" end
  if c.nZones >= 3 then bad[#bad + 1] = ("travels through %d zones"):format(c.nZones) end
  if c.group > 0 then bad[#bad + 1] = (c.group > 1 and "%d steps need a group" or "%d step needs a group"):format(c.group) end
  if c.maxReq > level + 1 then bad[#bad + 1] = ("last steps need level %d"):format(c.maxReq) end
  if c.maxL < level - 4 then bad[#bad + 1] = "low level for you now" end

  local perStep = c.pct / n
  local score = perStep + (lastUp and 3 or (#c.upgrades > 0 and 1.5 or 0)) - (c.nZones >= 3 and 1 or 0) - c.group * 0.5
  if c.done == n then c.verdict = GREY .. "Done|r"
  elseif c.dungeon and not ns.IsDone(c.dungeon) then c.verdict = "|cffa335eeImportant: it leads to a dungeon quest|r"
  elseif score >= 3.5 or (lastUp and c.group == 0) then c.verdict = GREEN .. "Do it|r"
  elseif score >= 1.5 then c.verdict = YELLOW .. "Worth it if you're nearby|r"
  else c.verdict = RED .. "Skip it|r" end
  c.good, c.bad = good, bad
  return c
end

-- First quest of the chain this quest belongs to (nil if it isn't in a chain).
function ns.ChainStart(id)
  local steps, here = ns.ChainSteps(id)
  if steps then return steps[1], here end
end

-- Where the chain starts: first quest, its giver, zone, coordinates, distance.
function StartLines(c) -- assigns the local declared at the top
  local first = c.steps[1]
  local q = ns.quests[first]
  if c.here == 1 then return { BLUE .. "Chain starts:|r " .. GREEN .. "with this quest|r" } end
  local done = ns.IsDone(first) and (GREEN .. " (you did it)|r") or ""
  local out = { BLUE .. "Chain starts:|r " .. YELLOW .. q[F.NAME] .. "|r" .. GREY .. (" [%d]"):format(q[F.LVL]) .. "|r" .. done }
  if q[F.GIVER] > 0 then
    local where, away = ns.Where(q[F.GMAP], q[F.GX], q[F.GY], ns.zones[q[F.ZONE]])
    out[#out + 1] = "    from " .. YELLOW .. ns.givers[q[F.GIVER]] .. "|r, " .. where .. (away and (GREY .. ", " .. away .. "|r") or "")
  else
    out[#out + 1] = "    " .. GREY .. "starts from an item or object in " .. ns.zones[q[F.ZONE]] .. "|r"
  end
  return out
end

-- Lines for the details panel. Short = one line for hover tooltips.
function ns.ChainLines(id, short)
  local c = ns.ChainReport(id)
  if not c then return nil end
  local n = #c.steps
  local start = StartLines(c)
  if short then
    local out = { GREY .. ("Chain: step %d of %d, %s XP total, popularity ~%d. "):format(c.here, n, ns.Commas(c.xp), c.pop) .. "|r" .. c.verdict }
    for _, l in ipairs(start) do out[#out + 1] = l end
    return out
  end
  local lines = {}
  lines[#lines + 1] = YELLOW .. ("Quest chain (%d steps, levels %d-%d, you're on step %d)"):format(n, c.minL, c.maxL, c.here) .. "|r"
  for i, sid in ipairs(c.steps) do
    local q = ns.quests[sid]
    local mark = ns.IsDone(sid) and (GREEN .. "done|r") or (i == c.here and (YELLOW .. "this one|r") or "")
    local tag = q[F.KIND] == 1 and " |cffff8040elite|r" or (q[F.KIND] == 2 and " |cffff8040dungeon|r" or "")
    lines[#lines + 1] = ("  %d. %s%s [%d] %s %s"):format(i, (i == c.here) and YELLOW or "|cffffffff", q[F.NAME] .. "|r", q[F.LVL], tag, mark)
    -- what each chain quest asks you to do
    if ns.StepLines and sid ~= id then
      for _, l in ipairs(ns.StepLines(sid, "        ", true)) do lines[#lines + 1] = GREY .. l:gsub("|r", "|r" .. GREY) .. "|r" end
    end
  end
  lines[#lines + 1] = ("Total: %s XP (%.0f%% of a level), %s, popularity ~%d/100 (estimate)"):format(
    ns.Commas(c.xp), c.pct, ns.Money(c.copper), c.pop)
  lines[#lines + 1] = "Do the chain? " .. c.verdict
  if #c.good > 0 then lines[#lines + 1] = GREEN .. "+ " .. table.concat(c.good, ", ") .. "|r" end
  if #c.bad > 0 then lines[#lines + 1] = RED .. "- " .. table.concat(c.bad, ", ") .. "|r" end
  return lines
end
