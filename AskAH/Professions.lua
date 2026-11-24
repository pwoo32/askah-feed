-- Professions.lua
-- Learns your professions and recipes so item tooltips can say
-- "you need this to level Engineering".
--
-- Skill levels come from GetProfessions()/GetProfessionInfo() at any time.
-- Recipes and their reagents can only be read while a profession window is
-- open, so open each profession (and Mining's Smelting) once; AskAH
-- remembers it and refreshes every time you open it again.
local _, ns = ...
local P = {}
ns.Prof = P

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, f2, g, h, i, j = pcall(f, ...)
  if ok then return a, b, c, d, e, f2, g, h, i, j end
end

local function Char() return ns.Data.Char() end

-- Profession names as the Skills list shows them.
local PROFS = { Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
  Herbalism = true, Leatherworking = true, Mining = true, Skinning = true, Tailoring = true,
  Jewelcrafting = true, Cooking = true, ["First Aid"] = true, Fishing = true }
P.PROFS = PROFS

-- relativeDifficulty: 0 orange (optimal), 1 yellow (medium), 2 green (easy), 3 grey (trivial)
local DIFF_NAME = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
local DIFF_COLOR = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }
P.DIFF_NAME, P.DIFF_COLOR = DIFF_NAME, DIFF_COLOR

-------------------------------------------------------------------------------
-- Skill levels
-------------------------------------------------------------------------------
function P.ReadSkills()
  if not AskAHDB then return end
  local c = Char()
  c.professions = c.professions or {}
  -- Classic-era client (WoW: Forever): professions are lines in the Skills list.
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, (try(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
      if name and not isHeader and PROFS[name] then
        local p = c.professions[name] or {}
        p.skill, p.max, p.updated = rank, maxRank, time()
        c.professions[name] = p
      end
    end
  end
  local idx = { try(GetProfessions) }
  for i = 1, 6 do
    local index = idx[i]
    if index then
      local name, _, rank, maxRank = try(GetProfessionInfo, index)
      if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
        local p = c.professions[name] or {}
        p.skill, p.max, p.updated = rank, maxRank, time()
        c.professions[name] = p
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Recipes (while a profession window is open)
-------------------------------------------------------------------------------
local function OpenProfession()
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
    local info = try(C_TradeSkillUI.GetBaseProfessionInfo)
    if info and info.professionName and info.professionName ~= "" then
      return info.professionName, info.skillLevel, info.maxSkillLevel
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
    local _, name, rank, maxRank = try(C_TradeSkillUI.GetTradeSkillLine)
    if name then return name, rank, maxRank end
  end
end

local index -- itemID -> list of uses, rebuilt lazily

-- Classic-era trade skill window (and Enchanting's craft window).
local DIFF = { optimal = 0, difficult = 0, medium = 1, easy = 2, trivial = 3 }
local function ItemIDOf(link) return link and tonumber(link:match("item:(%d+)")) end

local function SaveRecipes(prof, skill, maxSkill, recipes)
  if not prof or #recipes == 0 then return end
  local c = Char()
  c.recipes = c.recipes or {}
  c.recipes[prof] = { list = recipes, skill = skill, max = maxSkill, t = time() }
  c.professions = c.professions or {}
  local p = c.professions[prof] or {}
  if skill and skill > 0 then p.skill, p.max = skill, maxSkill end
  p.updated = time()
  c.professions[prof] = p
  index = nil
end

local function ScanClassicTrade()
  if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return false end
  local prof, skill, maxSkill = try(GetTradeSkillLine)
  if not prof or prof == "UNKNOWN" then return false end
  local recipes = {}
  for i = 1, (try(GetNumTradeSkills) or 0) do
    local name, kind = try(GetTradeSkillInfo, i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local reagents = {}
      for j = 1, (try(GetTradeSkillNumReagents, i) or 0) do
        local id = ItemIDOf(try(GetTradeSkillReagentItemLink, i, j))
        local _, _, qty = try(GetTradeSkillReagentInfo, i, j)
        if id and qty then reagents[id] = (reagents[id] or 0) + qty end
      end
      if next(reagents) then
        -- what it makes, so the deals window can check crafting profit
        local out = ItemIDOf(try(GetTradeSkillItemLink, i))
        local lo, hi = try(GetTradeSkillNumMade, i)
        recipes[#recipes + 1] = { n = name, d = DIFF[kind] or 3, r = reagents, o = out,
                                  mk = ((lo or 1) + (hi or lo or 1)) / 2 }
      end
    end
  end
  SaveRecipes(prof, skill, maxSkill, recipes)
  return #recipes > 0
end

local function ScanClassicCraft()
  if not (GetCraftDisplaySkillLine and GetNumCrafts and GetCraftInfo) then return false end
  local prof, skill, maxSkill = try(GetCraftDisplaySkillLine)
  if not prof then return false end
  local recipes = {}
  for i = 1, (try(GetNumCrafts) or 0) do
    local name, _, kind = try(GetCraftInfo, i)
    if name and kind ~= "header" then
      local reagents = {}
      for j = 1, (try(GetCraftNumReagents, i) or 0) do
        local id = ItemIDOf(try(GetCraftReagentItemLink, i, j))
        local _, _, qty = try(GetCraftReagentInfo, i, j)
        if id and qty then reagents[id] = (reagents[id] or 0) + qty end
      end
      if next(reagents) then recipes[#recipes + 1] = { n = name, d = DIFF[kind] or 3, r = reagents } end
    end
  end
  SaveRecipes(prof, skill, maxSkill, recipes)
  return #recipes > 0
end

function P.ScanRecipes(event)
  if not AskAHDB then return end
  if event and event:find("^CRAFT") then ScanClassicCraft() return end
  if ScanClassicTrade() then return end
  if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then return end
  local prof, skill, maxSkill = OpenProfession()
  if not prof then return end
  local ids = try(C_TradeSkillUI.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return end

  local recipes = {}
  for _, id in ipairs(ids) do
    local info = try(C_TradeSkillUI.GetRecipeInfo, id)
    if info and info.learned and info.name then
      local schem = try(C_TradeSkillUI.GetRecipeSchematic, id, false)
      local reagents = {}
      if schem and schem.reagentSlotSchematics then
        for _, slot in ipairs(schem.reagentSlotSchematics) do
          local r = slot.reagents and slot.reagents[1]
          if r and r.itemID and slot.quantityRequired then
            reagents[r.itemID] = (reagents[r.itemID] or 0) + slot.quantityRequired
          end
        end
      end
      if next(reagents) then
        recipes[#recipes + 1] = { n = info.name, d = info.relativeDifficulty, r = reagents }
      end
    end
  end
  if #recipes == 0 then return end

  local c = Char()
  c.recipes = c.recipes or {}
  c.recipes[prof] = { list = recipes, skill = skill, max = maxSkill, t = time() }
  c.professions = c.professions or {}
  local p = c.professions[prof] or {}
  if skill then p.skill, p.max = skill, maxSkill end
  p.updated = time()
  c.professions[prof] = p
  index = nil
end

-------------------------------------------------------------------------------
-- Tooltip lookup
-------------------------------------------------------------------------------
local function BuildIndex()
  index = {}
  for prof, data in pairs(Char().recipes or {}) do
    for _, rec in ipairs(data.list or {}) do
      for itemID, qty in pairs(rec.r) do
        index[itemID] = index[itemID] or {}
        table.insert(index[itemID], { prof = prof, n = rec.n, d = rec.d, q = qty })
      end
    end
  end
end

-- Returns a list of uses that still give skill-ups (orange/yellow),
-- best first, plus whether any recipe uses it at all.
function P.Needs(itemID)
  if not AskAHDB then return nil end
  if not index then BuildIndex() end
  local uses = index[itemID]
  if not uses then return nil end
  local useful = {}
  for _, u in ipairs(uses) do
    if u.d == 0 or u.d == 1 then useful[#useful + 1] = u end
  end
  table.sort(useful, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.q < b.q
  end)
  return useful, true
end

-------------------------------------------------------------------------------
-- Guide lookup: is this item on the standard leveling path for a profession
-- you have, from your current skill up to max?
-------------------------------------------------------------------------------
-- Returns { { prof, skill, steps = { {from, to, recipe, qty} }, total, now } }
function P.GuideNeeds(itemID)
  if not (AskAHDB and ns.Guides and itemID) then return nil end
  local out = {}
  for prof, info in pairs(Char().professions or {}) do
    local sites = ns.Guides[prof]
    local skill = info.skill or 0
    local cap = math.max(info.max or 300, 75)
    if sites and skill < 300 then
      local best
      local per = {}
      for site, guide in pairs(sites) do
        local hit = { prof = prof, skill = skill, steps = {}, total = 0, site = site }
        for _, st in ipairs(guide) do
          local from, to, rec, crafts, mats = st[1], st[2], st[3], st[4], st[5]
          local q1 = mats[itemID]
          if q1 and to > skill then
            local left = crafts
            if skill > from then left = math.ceil(crafts * (to - skill) / (to - from)) end
            local qty = q1 * left
            hit.steps[#hit.steps + 1] = { from = from, to = to, rec = rec, qty = qty, now = skill >= from,
                                          trainable = from <= cap }
            hit.total = hit.total + qty
            if skill >= from then hit.now = true end
          end
        end
        if #hit.steps > 0 then
          per[#per + 1] = { site = site, total = math.floor(hit.total + 0.5) }
          if not best or hit.total > best.total then best = hit end
        end
      end
      if best then
        table.sort(per, function(x, y) return x.total > y.total end)
        best.sites = per
        best.total = math.floor(best.total + 0.5)
        out[#out + 1] = best
      end
    end
  end
  table.sort(out, function(a, b) return (a.now and 1 or 0) > (b.now and 1 or 0) end)
  return out
end

-- Every guide (all professions, yours or not) that uses this item:
-- { { prof, total, from, to, sites = {names}, mine, skill, past } }.
-- total is the biggest 1-300 amount among the guide sites.
function P.GuideAll(itemID)
  if not (ns.Guides and itemID) then return nil end
  local mine = (AskAHDB and Char().professions) or {}
  local out = {}
  for prof, sites in pairs(ns.Guides) do
    local total, from, to, names = 0, nil, nil, {}
    for site, guide in pairs(sites) do
      local t = 0
      for _, st in ipairs(guide) do
        local q1 = st[5][itemID]
        if q1 then
          t = t + q1 * st[4]
          from = math.min(from or st[1], st[1])
          to = math.max(to or st[2], st[2])
        end
      end
      if t > 0 then
        names[#names + 1] = site
        total = math.max(total, t)
      end
    end
    if total > 0 then
      table.sort(names)
      local m = mine[prof]
      out[#out + 1] = { prof = prof, total = math.floor(total + 0.5), from = from, to = to, sites = names,
                        mine = m ~= nil, skill = m and m.skill, past = m and m.skill and m.skill >= to or false }
    end
  end
  table.sort(out, function(a, b) return a.total > b.total end)
  return out
end

-- Recipe items (Pattern:, Plans:, Schematic:, Formula:, Recipe:, Manual:):
-- is the recipe they teach a step on any leveling guide?
-- Returns { { prof, from, to, crafts, sites = {names}, mine, skill, past } } or nil.
local recipeIndex
local function Norm(s) return (s:lower():gsub("[^%w]", "")) end
local function BuildRecipeIndex()
  recipeIndex = {}
  for prof, sites in pairs(ns.Guides or {}) do
    for site, guide in pairs(sites) do
      for _, st in ipairs(guide) do
        local k = Norm(st[3])
        recipeIndex[k] = recipeIndex[k] or {}
        local list = recipeIndex[k]
        list[#list + 1] = { prof = prof, site = site, from = st[1], to = st[2], crafts = st[4] }
      end
    end
  end
end
P.RECIPE_PREFIXES = { "Pattern", "Plans", "Schematic", "Formula", "Recipe", "Manual" }
function P.GuideRecipe(itemName)
  if not (ns.Guides and itemName) then return nil end
  local taught
  for _, pre in ipairs(P.RECIPE_PREFIXES) do
    taught = taught or itemName:match("^" .. pre .. ": (.+)$")
  end
  if not taught then return nil end
  if not recipeIndex then BuildRecipeIndex() end
  local hits = recipeIndex[Norm(taught)]
  if not hits then return {}, taught end
  local byProf = {}
  local mine = (AskAHDB and Char().professions) or {}
  for _, h in ipairs(hits) do
    local g = byProf[h.prof]
    if not g then
      local m = mine[h.prof]
      g = { prof = h.prof, from = h.from, to = h.to, crafts = 0, sites = {}, seen = {},
            mine = m ~= nil, skill = m and m.skill }
      byProf[h.prof] = g
    end
    g.from, g.to = math.min(g.from, h.from), math.max(g.to, h.to)
    g.crafts = math.max(g.crafts, h.crafts)
    if not g.seen[h.site] then g.seen[h.site] = true; g.sites[#g.sites + 1] = h.site end
  end
  local out = {}
  for _, g in pairs(byProf) do
    table.sort(g.sites)
    g.past = g.mine and g.skill and g.skill >= g.to or false
    out[#out + 1] = g
  end
  table.sort(out, function(a, b) return a.from < b.from end)
  return out, taught
end

-- /askah guides: what's loaded and what AskAH thinks your skills are.
function P.GuideReport(itemID)
  local lines = {}
  if not ns.Guides then
    lines[1] = "the guide data didn't load. Quit the game fully and start it again (a /reload doesn't load new addon files)."
    return lines
  end
  local profs, steps, siteSet = {}, 0, {}
  for prof, sites in pairs(ns.Guides) do
    profs[#profs + 1] = prof
    for site, guide in pairs(sites) do siteSet[site] = true; steps = steps + #guide end
  end
  table.sort(profs)
  local sl = {}
  for s in pairs(siteSet) do sl[#sl + 1] = s end
  table.sort(sl)
  lines[#lines + 1] = ("guides loaded: %d professions, %d steps, from %s."):format(#profs, steps, table.concat(sl, " and "))
  lines[#lines + 1] = "  " .. table.concat(profs, ", ")
  P.ReadSkills()
  local you = {}
  for prof, info in pairs((AskAHDB and Char().professions) or {}) do
    you[#you + 1] = ("%s %d"):format(prof, info.skill or 0)
  end
  table.sort(you)
  lines[#lines + 1] = "your skills: " .. (#you > 0 and table.concat(you, ", ") or "none found yet (open your Skills tab once)")
  if itemID then
    local all = P.GuideAll(itemID) or {}
    lines[#lines + 1] = ("item %d is on %d profession guide(s)."):format(itemID, #all)
  end
  return lines
end

-- Rough count to keep leveling with the best recipe: orange gives a point
-- every craft, yellow roughly every other; count about 10 skill points.
function P.Estimate(u)
  local crafts = (u.d == 0) and 10 or 20
  return u.q * crafts
end

-- Is the recipe data older than your current skill? (open the window again)
function P.Stale(prof)
  local c = Char()
  local r = c.recipes and c.recipes[prof]
  local p = c.professions and c.professions[prof]
  return r and p and p.skill and r.skill and p.skill > r.skill + 4
end

function P.KnownCount()
  local n = 0
  for _ in pairs(Char().recipes or {}) do n = n + 1 end
  return n
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED",
  "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "CHAT_MSG_SKILL" }) do
  pcall(f.RegisterEvent, f, ev)
end
local pending = false
f:SetScript("OnEvent", function(_, event)
  if not AskAHDB then return end
  if event == "PLAYER_ENTERING_WORLD" or event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
    P.ReadSkills()
    return
  end
  -- debounce recipe scans; the list fires several updates when opening
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    P.ScanRecipes(event)
    P.ReadSkills()
  end)
end)
