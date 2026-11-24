-- Core.lua
-- Slash commands, search, saved notes, and the auction house hook.
local addonName, ns = ...

local PREFIX = "|cff33ccffAskAH|r: "
local function Print(msg) print(PREFIX .. msg) end
ns.Print = Print

-- Lower-case text used for keyword search.
local function Haystack(entry)
  return (entry.q .. " " .. entry.a .. " " .. (entry.keywords or "") .. " " .. entry.topic):lower()
end

-- Return entries matching every word in the query.
function ns.Search(query)
  local results = {}
  local words = {}
  for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
  if #words == 0 then return results end

  local all = ns.AllEntries()
  for _, entry in ipairs(all) do
    local hay = Haystack(entry)
    local ok = true
    for _, w in ipairs(words) do
      if not hay:find(w, 1, true) then ok = false; break end
    end
    if ok then results[#results + 1] = entry end
  end
  return results
end

-- Gold and leveling guide for this character plus questions you add with /askah add.
function ns.AllEntries()
  local all = {}
  for _, e in ipairs(ns.Routes.Entries()) do all[#all + 1] = e end
  for _, e in ipairs(AskAHDB.custom) do all[#all + 1] = e end
  return all
end

local function PrintEntry(entry)
  Print("|cffffd200" .. entry.q .. "|r")
  for line in entry.a:gmatch("[^\n]+") do print("   " .. line) end
end

-- /askah help: grouped by topic, command in yellow, what it does in white.
local HELP = {
  { "Selling and prices", {
    { "price <item>", "last-seen AH price" },
    { "worth", "your bags valued at AH prices" },
    { "deals", "AH deals window" },
    { "sales", "your AH sales (chat, unsold, clear)" },
    { "auctions", "your auctions that are up now, from anywhere" },
    { "accuracy", "how well the sell chances have matched what really sold" },
    { "losses [days]", "AH cut and lost deposits, per AH and per item that didn't sell" },
    { "scan", "scan the whole AH (stand at the AH)" },
  } },
  { "Gear and crafting", {
    { "upgrades", "gear for sale that's an upgrade for you" },
    { "craft <profession>", "most profitable recipes to craft" },
    { "spec <spec>", "which spec gear advice uses (auto, prot, arms, fury, ...)" },
    { "focus threat|balanced|survival", "Prot gear advice: favor damage/threat, both, or staying alive" },
    { "gear", "save your worn and bagged gear with AskAH's scores, to check its picks" },
    { "pawn [auto|off|<scale>]", "score gear with your Ask Mr. Robot scale in Pawn (auto), or not" },
  } },
  { "Guide and character", {
    { "<words>", "search the gold/leveling guide, e.g. /askah leather" },
    { "add Question? = Answer", "save your own entry (mine, remove <n>)" },
    { "stats, bags", "your character stats or bags" },
  } },
  { "Data", {
    { "feed", "hourly Blizzard AH data status (feed group 1-5)" },
    { "blizz", "Blizzard item/recipe/quest data status" },
    { "guides [item]", "check the profession guides loaded" },
    { "ahtype auto|neutral|faction", "if it mixes up the goblin AH" },
  } },
  { "Settings", {
    { "options", "open the AskAH settings page" },
    { "tooltip on|off|full|compact", "tooltip info; full shows Shift detail always" },
    { "deals on|off", "deals window pops up with the AH" },
    { "autoscan on|off", "scan the AH when you open it" },
    { "minimap on|off", "the minimap button" },
    { "ah on|off", "open the guide next to the AH" },
  } },
}

local function ShowHelp()
  Print("commands (type /askah then the command). Switches are also in Esc > Options > AddOns > AskAH.")
  for _, group in ipairs(HELP) do
    print("  |cff33ccff" .. group[1] .. "|r")
    for _, c in ipairs(group[2]) do
      print(("     |cffffd200%s|r  %s"):format(c[1], c[2]))
    end
  end
end

SLASH_ASKAH1 = "/askah"
SLASH_ASKAH2 = "/ahhelp"
SlashCmdList.ASKAH = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower()

  if msg == "" then
    ns.ToggleWindow()
  elseif cmd == "help" then
    ShowHelp()
  elseif cmd == "add" then
    local q, a = rest:match("^(.-)%s*=%s*(.+)$")
    if not q or q == "" then
      Print("usage: /askah add Question? = Answer")
      return
    end
    table.insert(AskAHDB.custom, { topic = "My questions", q = q, a = a, keywords = "" })
    Print("saved: " .. q)
    ns.RefreshWindow()
  elseif cmd == "mine" then
    if #AskAHDB.custom == 0 then Print("you haven't saved any questions yet.") return end
    Print("your saved questions:")
    for i, e in ipairs(AskAHDB.custom) do print(("   |cffffd200%d.|r %s"):format(i, e.q)) end
  elseif cmd == "remove" then
    local i = tonumber(rest)
    if i and AskAHDB.custom[i] then
      local removed = table.remove(AskAHDB.custom, i)
      Print("removed: " .. removed.q)
      ns.RefreshWindow()
    else
      Print("usage: /askah remove <number>  (see /askah mine)")
    end
  elseif cmd == "ah" then
    local v = rest:lower()
    if v == "on" or v == "off" then
      AskAHDB.openWithAH = (v == "on")
      Print("open with auction house: " .. v)
    else
      Print("usage: /askah ah on|off")
    end
  elseif cmd == "scan" then
    ns.Data.Scan()
  elseif cmd == "price" then
    local rows = ns.Data.FindPrices(rest)
    if rest == "" then Print("usage: /askah price <item name>") return end
    if #rows == 0 then Print("no AH price saved for \"" .. rest .. "\". Search it at the AH or run /askah scan.") return end
    for i = 1, math.min(#rows, 8) do
      local r = rows[i]
      print(("   |cffffd200%s|r  %s each  |cff999999%d listed, %s|r"):format(r.n, ns.Data.Money(r.p), r.q or 0, ns.Data.Ago(r.t)))
    end
    if #rows > 8 then Print(("%d more matches in the Prices tab."):format(#rows - 8)) end
  elseif cmd == "stats" then
    ns.Data.SnapshotStats()
    ns.ShowWindow(nil, "stats")
  elseif cmd == "bags" then
    ns.Data.SnapshotInventory()
    ns.ShowWindow(nil, "bags")
  elseif cmd == "worth" then
    ns.Data.SnapshotInventory()
    local sum, rows = ns.Data.Worth()
    Print("your bags are worth about " .. ns.Data.Money(sum) .. " at last-seen AH prices.")
    for i = 1, math.min(#rows, 5) do
      print(("   %dx |cffffd200%s|r  %s"):format(rows[i].c, rows[i].n, ns.Data.Money(rows[i].v)))
    end
  elseif cmd == "spec" then
    local v = rest:upper()
    local ok = { AUTO = 1, PROT = 1, ARMS = 1, FURY = 1, ROGUE = 1, HUNTER = 1, CASTER = 1, HEALER = 1, HYBRID = 1 }
    if ok[v] then
      AskAHDB.spec = (v == "AUTO") and "auto" or v
      Print("gear advice now uses: " .. (ns.Tooltip.SPEC_NAMES[ns.Tooltip.Spec()] or v) .. (v == "AUTO" and " (auto)" or ""))
    else
      Print("current spec for gear advice: " .. (ns.Tooltip.SPEC_NAMES[ns.Tooltip.Spec()] or "?"))
      print("   /askah spec auto|prot|arms|fury|rogue|hunter|caster|healer|hybrid")
    end
  elseif cmd == "gear" then
    local e, b = ns.Tooltip.Snapshot()
    Print(("saved what I see about your %d worn items and %d gear items in your bags. Type /reload so it's written to disk."):format(e, b))
  elseif cmd == "pawn" then
    local v = strtrim(rest or "")
    local E = ns.Effects
    if v:lower() == "off" then AskAHDB.pawnScale = "off"; Print("gear advice uses AskAH's own weights.")
    elseif v:lower() == "auto" then AskAHDB.pawnScale = nil; Print("gear advice uses your Ask Mr. Robot scale when Pawn has one.")
    elseif v ~= "" then AskAHDB.pawnScale = v; Print("gear advice uses the Pawn scale \"" .. v .. "\" when it's there.") end
    if v == "" or (v:lower() ~= "off") then
      if type(PawnGetAllScalesEx) ~= "function" then
        Print("Pawn isn't loaded. Install Pawn and AskMrRobot, then /reload. Until then AskAH uses its own weights.")
      else
        local name, label = E.PawnScale()
        Print(name and ("using Pawn scale: " .. tostring(label)) or "no Ask Mr. Robot scale in Pawn yet (on askmrrobot.com: Send to Addon, then /reload). Using AskAH's weights.")
        local list = E.PawnScales() or {}
        local names = {}
        for _, sc in ipairs(list) do names[#names + 1] = tostring(sc.LocalizedName or sc.Name) end
        if #names > 0 then print("   Pawn scales: " .. table.concat(names, ", ")) end
      end
    end
  elseif cmd == "focus" then
    local v = rest:lower()
    if v == "threat" or v == "survival" or v == "balanced" then
      AskAHDB.focus = (v ~= "balanced") and v or nil
      Print("Prot gear advice now favors: " .. v .. (v == "threat" and " (Strength, crit, hit, weapon)" or v == "survival" and " (Stamina, armor, avoidance)" or ""))
    else
      Print("Prot gear focus: " .. (AskAHDB.focus or "balanced") .. ".  /askah focus threat|balanced|survival")
    end
  elseif cmd == "ahtype" then
    local v = rest:lower()
    if v == "auto" or v == "neutral" or v == "faction" then
      AskAHDB.ahType = (v ~= "auto") and v or nil
      Print("auction house type: " .. v .. " (applies next time you open it)")
    else
      Print("usage: /askah ahtype auto|neutral|faction  (if AskAH guesses the wrong AH)")
    end
  elseif cmd == "feed" then
    if ns.Feed then ns.Feed.Command(rest) else Print("feed code didn't load (restart the game after updating AskAH).") end
  elseif cmd == "upgrades" or cmd == "upgrade" then
    if ns.Blizz then ns.Blizz.UpgradesReport(tonumber(rest)) end
  elseif cmd == "craft" or cmd == "crafting" then
    if ns.Blizz then ns.Blizz.CraftReport(rest) end
  elseif cmd == "blizz" or cmd == "blizzard" then
    if ns.Blizz then ns.Blizz.Status() end
  elseif cmd == "autoscan" then
    local v = rest:lower()
    if v == "on" or v == "off" then
      AskAHDB.autoScan = (v == "on")
      Print("auto-scan when you open the auction house: " .. v)
    else
      Print("auto-scan is " .. (AskAHDB.autoScan == false and "off" or "on") .. ". Use /askah autoscan on|off")
    end
  elseif cmd == "tooltip" then
    local v = rest:lower()
    if v == "on" or v == "off" then
      AskAHDB.tooltip = (v == "on")
      Print("tooltip info: " .. v)
    elseif v == "full" or v == "compact" then
      AskAHDB.ttDetail = (v == "full") and "always" or nil
      Print(v == "full" and "tooltips show all detail." or "tooltips are compact. Hold Shift for detail.")
    else
      Print("usage: /askah tooltip on|off|full|compact")
    end
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif cmd == "deals" then
    local v = rest:lower()
    if v == "on" or v == "off" then
      AskAHDB.dealsPopup = (v == "on")
      Print("deals window pops up with the AH: " .. v)
    elseif ns.Deals then
      ns.Deals.Toggle()
    end
  elseif cmd == "sales" or cmd == "sold" then
    local v, n = rest:lower():match("^(%S*)%s*(%d*)$")
    if not ns.Sales then Print("sales code didn't load (restart the game after updating AskAH).")
    elseif v == "chat" then ns.Sales.PrintChat(tonumber(n) or 10)
    elseif v == "unsold" or v == "expired" then ns.Sales.PrintChat(tonumber(n) or 15, "unsold")
    elseif v == "sold" then ns.Sales.PrintChat(tonumber(n) or 10, "sold")
    elseif v == "clear" then ns.Sales.Clear()
    elseif v == "debug" then ns.Sales.Debug()
    elseif v == "watch" then
      AskAHDB.debug = not AskAHDB.debug or nil
      Print(AskAHDB.debug and "sales watch on: each auction alert from the game is printed in chat. /askah sales watch again to stop."
                          or "sales watch off.")
    else ns.Sales.Toggle() end
  elseif cmd == "losses" or cmd == "loss" then
    if ns.Sell and ns.Sell.Losses then ns.Sell.Losses(tonumber(rest)) end
  elseif cmd == "accuracy" then
    if ns.Sell and ns.Sell.Accuracy then ns.Sell.Accuracy() end
  elseif cmd == "auctions" then
    if not ns.Sales then return end
    local v = rest:lower()
    if v == "chat" then ns.Sales.PrintActive()
    elseif v == "debug" then ns.Sales.DebugAuctions()
    else ns.Sales.ShowView("active") end
  elseif cmd == "minimap" then
    local v = rest:lower()
    if v == "on" or v == "off" then
      AskAHDB.minimap = AskAHDB.minimap or {}
      AskAHDB.minimap.hide = (v == "off") or nil
      if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
      Print("minimap button: " .. v)
    else
      Print("usage: /askah minimap on|off")
    end
  elseif cmd == "guides" then
    local id = tonumber(rest) or (rest ~= "" and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(rest)) or nil
    for _, l in ipairs(ns.Prof and ns.Prof.GuideReport and ns.Prof.GuideReport(id) or { "profession code didn't load." }) do Print(l) end
  elseif cmd == "tab" then
    ns.ShowWindow(nil, rest:lower())
  else
    local results = ns.Search(msg)
    if #results == 0 then
      Print("no answer found for \"" .. msg .. "\". Try fewer words, or /askah help.")
    else
      for i = 1, math.min(#results, 3) do PrintEntry(results[i]) end
      if #results > 3 then Print(("%d more in the window (/askah)."):format(#results - 3)) end
    end
  end
end

-- Events ---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    AskAHDB = AskAHDB or {}
    AskAHDB.custom = AskAHDB.custom or {}
    if AskAHDB.openWithAH == nil then AskAHDB.openWithAH = false end
    -- Say hello once per version, not on every login.
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ver = meta and meta(addonName, "Version") or "?"
    if AskAHDB.helloVersion ~= ver then
      AskAHDB.helloVersion = ver
      Print(("v%s loaded. Hover an item for prices and advice (Shift for more). /askah help"):format(ver or "?"))
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if ns.AttachAHButton then C_Timer.After(0, function() pcall(ns.AttachAHButton) end) end
    if AskAHDB.openWithAH then ns.ShowWindow("Auction House", "guide") end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if ns.DetachAHButton then ns.DetachAHButton() end
    if AskAHDB.openWithAH then ns.HideWindow() end
  end
end)
