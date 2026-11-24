-- Sales.lua
-- Your own auction house sales, newest first. The client has no sales history
-- API, so AskAH records sales from now on, from two places:
--   * your Auctions tab at the AH, where sold auctions show "Sold" until the
--     gold is mailed (C_AuctionHouse owned auctions)
--   * the auction house mail at the mailbox ("Sale Pending" / "Auction
--     successful"), read with GetInboxInvoiceInfo: price, buyer, AH cut,
--     deposit and what you actually got. The cut tells faction (5%) from
--     neutral (15%) AH.
-- Both are merged into one line per sale. Saved per character in AskAHDB.
-- /askah sales            open or close the window
-- /askah sales chat [n]   print the last n sales in chat
-- /askah sales clear      forget this character's sales
-- /askah sales unsold     list auctions that didn't sell (expired or cancelled)
-- /askah sales debug      show what the mailbox looks like to AskAH
local _, ns = ...
local S = {}
ns.Sales = S

local GREEN, YELLOW, GREY, BLUE, ORANGE = "|cff33ff33", "|cffffd200", "|cff999999", "|cff33ccff", "|cffff8040"
local GII = function(x) local B = AskAHBlizzAPI; if B and B.GetItemInfo then return B.GetItemInfo(x) end return ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(x) end -- Blizzard API data first, then the game
local MAX_KEEP = 500
local MATCH_WINDOW = 3 * 3600 -- a sold auction and its mail are at most ~1h apart

local function pass(ok, ...) if ok then return ... end end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  return pass(pcall(f, ...))
end

local function Coins(c)
  if ns.Deals and ns.Deals.Coins then return ns.Deals.Coins(c) end
  return ns.Data.Money(c)
end

function S.List()
  local c = ns.Data.Char()
  c.sales = c.sales or {}
  return c.sales
end

local function Sort(list)
  table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
  for i = #list, MAX_KEEP + 1, -1 do list[i] = nil end
end

-- itemID from a name: the item cache, else AskAH's own price data.
local idCache = {}
local function IdFor(name)
  if not name then return nil end
  if idCache[name] then return idCache[name] end
  local link = select(2, try(GII, name))
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id and AskAHDB.prices then
    for _, prices in pairs(AskAHDB.prices) do
      for itemID, e in pairs(prices) do
        if e.n == name then id = itemID; break end
      end
      if id then break end
    end
  end
  idCache[name] = id
  return id
end

local function Changed()
  if S.Refresh then S.Refresh() end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- Your Auctions tab: sold auctions sit there (status "Sold") until the gold
-- is mailed. Recorded when the auction house lists your auctions.
local function ReadOwned()
  local AH = C_AuctionHouse
  if not (AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then return end
  local SOLD = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
  local list = S.List()
  local seen = {}
  for _, e in ipairs(list) do if e.aid then seen[e.aid] = e end end
  local ahNow = ns.Data.IsNeutralOpen() and "neutral" or "faction"
  local added = false
  for i = 1, (try(AH.GetNumOwnedAuctions) or 0) do
    local o = try(AH.GetOwnedAuctionInfo, i)
    if o and o.status == SOLD and o.auctionID and not seen[o.auctionID] then
      local link = o.itemLink
      local id = o.itemKey and o.itemKey.itemID
      local name = (link and link:match("%[(.-)%]")) or (id and try(GII, id))
      local price = (o.buyoutAmount and o.buyoutAmount > 0) and o.buyoutAmount or o.bidAmount
      -- one mail-less line per sold auction; the mail fills in the rest later
      local per = price and o.quantity and o.quantity > 1 and price or nil
      local rec
      if name then
        for j = #list, 1, -1 do -- mail already read for this sale?
          local e = list[j]
          if not e.kind and e.n == name and e.mail and not e.aid and math.abs((e.t or 0) - time()) < MATCH_WINDOW
             and (not price or not e.bid or e.bid == price or (per and e.bid == per * o.quantity)) then
            rec = e; break
          end
        end
      end
      if not rec then
        rec = { n = name or ("item " .. tostring(id)), t = time(), ah = ahNow }
        table.insert(list, 1, rec)
        added = true
      end
      rec.aid, rec.id = o.auctionID, rec.id or id
      rec.q = rec.q or o.quantity
      rec.bid = rec.bid or price
      if o.bidder and o.bidder ~= "" then rec.buyer = rec.buyer or o.bidder end
      if not rec.mail then rec.ah = ahNow end
    end
  end
  if added then Sort(list); Changed() end
end

---------------------------------------------------------------------------
-- Your auctions that are up right now, saved whenever the AH lists them, so
-- you can look at them anywhere. One snapshot per AH (faction / neutral).
---------------------------------------------------------------------------
function S.Auctions()
  local c = ns.Data.Char()
  c.auctions = c.auctions or {}
  return c.auctions
end

local function AHNow() return ns.Data.IsNeutralOpen() and "neutral" or "faction" end

-- Modern AH (C_AuctionHouse): exact seconds left.
local function SnapshotModern()
  local AH = C_AuctionHouse
  local n = AH and try(AH.GetNumOwnedAuctions)
  if not n then return end
  local SOLD = (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold) or 1
  local now, out = time(), {}
  for i = 1, n do
    local o = try(AH.GetOwnedAuctionInfo, i)
    if o then
      local id = o.itemKey and o.itemKey.itemID
      out[#out + 1] = {
        aid = o.auctionID, id = id, q = o.quantity,
        n = (o.itemLink and o.itemLink:match("%[(.-)%]")) or (id and try(GII, id)) or ("item " .. tostring(id)),
        buyout = (o.buyoutAmount and o.buyoutAmount > 0) and o.buyoutAmount or nil,
        bid = (o.bidAmount and o.bidAmount > 0) and o.bidAmount or nil,
        exp = o.timeLeftSeconds and (now + o.timeLeftSeconds) or nil,
        sold = (o.status == SOLD) or nil, bidder = o.bidder,
      }
    end
  end
  S.Auctions()[AHNow()] = { t = now, list = out, api = "modern" }
end

-- Classic-style AH: time left comes as a band (short/medium/long/very long).
local TL_MAX = { 1800, 7200, 28800, 86400 }
local TL_MIN = { 0, 1800, 7200, 28800 }
local function SnapshotClassic()
  local n = try(GetNumAuctionItems, "owner")
  if not n then return end
  local now, out = time(), {}
  for i = 1, n do
    local name, _, count, _, _, _, _, minBid, _, buyout, bidAmount, _, bidder, _, _, saleStatus, itemID = try(GetAuctionItemInfo, "owner", i)
    if name then
      local tl = try(GetAuctionItemTimeLeft, "owner", i)
      out[#out + 1] = {
        id = itemID or IdFor(name), n = name, q = count,
        buyout = (buyout and buyout > 0) and buyout or nil,
        bid = (bidAmount and bidAmount > 0) and bidAmount or nil, minBid = minBid,
        exp = TL_MAX[tl or 0] and (now + TL_MAX[tl]) or nil,
        expMin = TL_MIN[tl or 0] and (now + TL_MIN[tl]) or nil,
        sold = (saleStatus == 1) or nil, bidder = bidder,
      }
    end
  end
  S.Auctions()[AHNow()] = { t = now, list = out, api = "classic" }
end

-- Something you just posted: shown straight away (marked "just posted") until
-- the AH's own list of your auctions comes back and replaces it.
local DUR = { 12 * 3600, 24 * 3600, 48 * 3600 }
local function AddPosted(id, link, q, buyout, bid, dur)
  if not id and not link then return end
  local snaps = S.Auctions()
  local w = AHNow()
  local snap = snaps[w] or { t = time(), list = {} }
  snaps[w] = snap
  snap.list = snap.list or {}
  local now = time()
  table.insert(snap.list, 1, {
    id = id, q = q or 1, posted = now,
    n = (link and link:match("%[(.-)%]")) or (id and try(GII, id)) or ("item " .. tostring(id)),
    buyout = (buyout and buyout > 0) and buyout or nil, bid = (bid and bid > 0) and bid or nil,
    exp = DUR[dur or 0] and (now + DUR[dur]) or nil,
  })
  -- remember the sell chance AskAH gave, to check it against the outcome later
  if id and ns.Sell and ns.Sell.RecordPrediction then
    local unit = buyout and buyout > 0 and q and q > 0 and math.floor(buyout / q) or nil
    if pcall(ns.Sell.RecordPrediction, id, w, q or 1, unit) and AskAHDB.preds and AskAHDB.preds[1] then
      -- the deposit really paid: your money drops right after posting
      local pd = S.pendingDep
      if not (pd and GetTime() - pd.at < 2) then pd = { at = GetTime(), money = S.lastMoney or GetMoney(), preds = {} }; S.pendingDep = pd end
      pd.preds[#pd.preds + 1] = AskAHDB.preds[1]
    end
  end
  Changed()
end

local function HookPosting()
  local AH = C_AuctionHouse
  if AH and hooksecurefunc then
    local function loc(item)
      local id = item and try(C_Item and C_Item.GetItemID, item)
      local link = item and try(C_Item and C_Item.GetItemLink, item)
      return id, link
    end
    if AH.PostItem then
      hooksecurefunc(AH, "PostItem", function(item, duration, quantity, bid, buyout)
        local id, link = loc(item)
        pcall(AddPosted, id, link, quantity, buyout, bid, duration)
      end)
    end
    if AH.PostCommodity then
      hooksecurefunc(AH, "PostCommodity", function(item, duration, quantity, unitPrice)
        local id, link = loc(item)
        pcall(AddPosted, id, link, quantity, unitPrice and quantity and unitPrice * quantity, nil, duration)
      end)
    end
  end
  if PostAuction and hooksecurefunc then
    hooksecurefunc("PostAuction", function(minBid, buyout, runTime, stackSize, numStacks)
      local name, _, count = try(GetAuctionSellItemInfo)
      local link = try(GetAuctionSellItemLink)
      local id = link and tonumber(link:match("item:(%d+)"))
      for _ = 1, math.max(1, numStacks or 1) do
        pcall(AddPosted, id or (name and IdFor(name)), link or (name and ("[" .. name .. "]")), stackSize or count, buyout, minBid, nil)
      end
    end)
  end
end
pcall(HookPosting)

-- Ask the AH for your auctions (so the list is fresh without opening the tab).
local function QueryOwned()
  if not ns.Data.IsAHOpen or ns.Data.IsAHOpen() ~= false then
    if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
      pcall(C_AuctionHouse.QueryOwnedAuctions, {})
    end
    if GetOwnerAuctionItems then pcall(GetOwnerAuctionItems) end
  end
end
-- The classic owner list may already be loaded (Blizzard's Auctions tab).
local function SnapshotAny()
  local m = C_AuctionHouse and try(C_AuctionHouse.GetNumOwnedAuctions)
  if m and m > 0 then pcall(ReadOwned); pcall(SnapshotModern) end
  local n = try(GetNumAuctionItems, "owner")
  if n and n > 0 then pcall(SnapshotClassic) end
end

-- Active auctions for display, each marked if a sale / expiry mail has come
-- in for it since the snapshot. Not-done ones first, ending soonest first.
function S.ActiveRows()
  local rows, used, now = {}, {}, time()
  local me = ns.Data.Char()
  for key, c in pairs(AskAHDB and AskAHDB.chars or {}) do
  local sales = c.sales or {}
  for ah, snap in pairs(c.auctions or {}) do
    for _, a in ipairs(snap.list or {}) do
      local r = {}
      for k, v in pairs(a) do r[k] = v end
      r.ah, r.seen, r.active = ah, snap.t, true
      if c ~= me then r.char = key:match("^(.-) %- ") or key end
      for _, e in ipairs(sales) do
        if not used[e] and a.aid and e.aid == a.aid and (e.t or 0) >= (snap.t or 0) - 3600 then
          used[e] = true
          r.done, r.doneT = e.kind or "sold", e.t
          break
        end
      end
      for _, e in ipairs(sales) do
        if r.done then break end
        if not used[e] and e.n == a.n and (e.t or 0) >= (snap.t or 0) - 3600 and not (e.aid and a.aid and e.aid ~= a.aid)
           and (not e.ah or e.ah == ah) and (not e.q or not a.q or e.q == a.q) then
          used[e] = true
          r.done, r.doneT = e.kind or "sold", e.t
          break
        end
      end
      if a.sold and not r.done then r.done = "sold" end
      -- the hourly Blizzard feed follows your auction IDs: gone with hours
      -- left = probably sold, gone at the very end = probably expired
      if not r.done then
        local f = a.aid and S.FeedStatus(a.aid) or S.FeedMatch(a)
        if f and f.status ~= "up" and f.t >= (snap.t or 0) then
          r.done, r.doneT, r.feed = (f.status == "sold") and "sold?" or (f.status == "expired" and "expired?" or "ended?"), f.t, true
        elseif f and f.status == "up" then
          if f.qNow < f.q0 then r.partial = f.q0 - f.qNow end
          -- Blizzard's view, if newer than your last AH visit: still up,
          -- time left band, and how many units are listed cheaper than yours
          if f.t >= (snap.t or 0) then
            r.api = f
            local TLMAX = { 1800, 7200, 43200, 172800 }
            local TLMIN = { 0, 1800, 7200, 43200 }
            if f.tl and TLMAX[f.tl] then
              r.exp = math.min(r.exp or math.huge, f.t + TLMAX[f.tl]); r.expMin = f.t + TLMIN[f.tl]
              if r.expMin > r.exp then r.expMin = nil end
            end
          end
        end
      end
      -- its time ran out and nothing said it sold: it expired (the mail confirms)
      if not r.done and r.exp and now > r.exp + 300 then
        r.done, r.doneT, r.timedOut = "expired?", r.exp, true
      end
      rows[#rows + 1] = r
    end
  end
  end
  table.sort(rows, function(x, y)
    if (x.done ~= nil) ~= (y.done ~= nil) then return not x.done end
    return (x.exp or math.huge) < (y.exp or math.huge)
  end)
  return rows
end

-- Chance one of your listings sells before it runs out, at its price and
-- with what's listed cheaper now (the feed's count, else your last scan).
function S.Chance(r)
  if not (r and r.id and ns.Sell and ns.Sell.Advise) then return nil end
  local unit = (r.buyout or r.bid) and r.q and r.q > 0 and (r.buyout or r.bid) / r.q
  if not unit then return nil end
  local w = r.ah == "neutral" and "neutral" or "faction"
  local ahead = 0
  if r.api and r.api.ahead then ahead = r.api.ahead
  else
    local e = ns.Data.Prices(w)[r.id]
    if e and e.p and e.p < unit then ahead = math.max(1, math.floor((e.spd or 1) + 0.5)) end
  end
  local ok, a = pcall(ns.Sell.Advise, r.id, r.q, false, { w = w, unit = unit, ahead = ahead })
  local x = ok and a and a.ah and a.ah[w]
  return x and x.chance
end

local function LeftText(r)
  if r.done == "sold" then return "|cff33ff33sold|r" end
  if r.done == "sold?" then return "|cff33ff33probably sold|r" end
  if r.done == "expired?" then return "|cffff4040probably expired|r" end
  if r.done == "ended?" then return GREY .. "gone (sold or expired)|r" end
  if r.done == "cancelled" then return ORANGE .. "cancelled|r" end
  if r.done then return "|cffff4040didn't sell|r" end
  if not r.exp then return GREY .. "?|r" end
  local left = r.exp - time()
  if left <= 0 then return GREY .. "ended?|r" end
  local function fmt(sec)
    if sec >= 3600 then return ("%dh"):format(math.floor(sec / 3600 + 0.5)) end
    return ("%dm"):format(math.max(1, math.floor(sec / 60)))
  end
  if r.expMin then
    local lo = math.max(0, r.expMin - time())
    return (lo > 0 and (fmt(lo) .. "-") or "<") .. fmt(left)
  end
  return fmt(left)
end
S.LeftText = LeftText

function S.PrintActive()
  local rows = S.ActiveRows()
  if #rows == 0 then
    ns.Print("no auctions saved yet. Open the auction house once (AskAH reads your Auctions tab), then this works anywhere.")
    return
  end
  ns.Print("your auctions (as of your last AH visit):")
  for _, r in ipairs(rows) do
    local link = r.id and select(2, try(GII, r.id))
    print(("   %s%s  %s  %s  %s"):format(link or (YELLOW .. r.n .. "|r"), (r.q and r.q > 1) and (" x" .. r.q) or "",
      r.buyout and Coins(r.buyout) or (r.bid and (Coins(r.bid) .. GREY .. " bid|r")) or "", LeftText(r),
      GREY .. (r.ah == "neutral" and "neutral AH" or "faction AH") .. (r.char and (", " .. r.char) or "") .. "|r"))
  end
end

-- Mail: one invoice per sale, while the mail sits in your inbox.
local function WhichAH(sender, bid, cut)
  if cut and bid and bid > 0 and cut > 0 then
    return (cut / bid) > 0.10 and "neutral" or "faction"
  end
  local s = (sender or ""):lower()
  if s:find("blackwater") or s:find("neutral") or s:find("goblin") then return "neutral" end
  if s:find("auction") then return "faction" end
end

-- "Auction successful: %s" (and Sale Pending) subjects, for when the invoice
-- details aren't available.
local function SubjectPattern(fmt, fallback)
  fmt = fmt or fallback
  fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
  return "^" .. fmt .. "$"
end
local SOLD_SUBJECT = SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s")
local PENDING_SUBJECT = SubjectPattern(AUCTION_INVOICE_MAIL_SUBJECT, "Sale Pending: %s")
local EXPIRED_SUBJECT = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s")
local CANCELLED_SUBJECT = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT, "Auction cancelled: %s")

-- An auction that didn't sell: the item comes back by mail ("Auction expired"
-- or "Auction cancelled"). Kept as kind = "expired" / "cancelled".
local function ReadUnsold(i, sender, subject, daysLeft, list, now, claimed)
  local name = subject and subject:match(EXPIRED_SUBJECT)
  local kind = name and "expired"
  if not name then
    name = subject and subject:match(CANCELLED_SUBJECT)
    kind = name and "cancelled"
  end
  if not name then return false end
  local iname, itemID, _, count = try(GetInboxItem, i, 1)
  local link = try(GetInboxItemLink, i, 1)
  if not itemID and link then itemID = tonumber(link:match("item:(%d+)")) end
  local base, qty = name:match("^(.-) %((%d+)%)$")
  if base then name = base end
  name = iname or name
  count = (type(count) == "number" and count > 0) and count or tonumber(qty)
  local arrived = daysLeft and (now - math.floor((30 - daysLeft) * 86400)) or now
  for _, e in ipairs(list) do
    if not claimed[e] and e.kind == kind and e.n == name and (e.q == count or not e.q or not count)
       and math.abs((e.mt or 0) - arrived) < 4 * 3600 then
      claimed[e] = true
      e.q = e.q or count
      e.id = e.id or itemID
      e.mail = true
      e.ah = e.ah or WhichAH(sender)
      return false
    end
  end
  local rec = { kind = kind, n = name, id = itemID or IdFor(name), q = count, t = arrived, mt = arrived,
                mail = true, ah = WhichAH(sender) }
  table.insert(list, rec)
  claimed[rec] = true
  return true
end

local function ReadOne(i, list, now, claimed)
  claimed = claimed or {}
  local _, _, sender, subject, money, _, daysLeft = try(GetInboxHeaderInfo, i)
  local kind, name, buyer, bid, buyout, deposit, cut, _, _, _, count = try(GetInboxInvoiceInfo, i)
  if kind ~= "seller" and kind ~= "seller_temp_invoice" then
    if ReadUnsold(i, sender, subject, daysLeft, list, now, claimed) then return true end
    -- no invoice: go by the subject line
    local sn = subject and subject:match(SOLD_SUBJECT)
    local pn = subject and subject:match(PENDING_SUBJECT)
    if not (sn or pn) then return false end
    kind, name = sn and "seller" or "seller_temp_invoice", sn or pn
    buyer, bid, buyout, deposit, cut = nil, nil, nil, nil, nil
  end
  if not name then return false end
  -- "Copper Ore (20)" in subjects on some clients
  local base, qty = name:match("^(.-) %((%d+)%)$")
  if base then name = base; count = count or tonumber(qty) end
  local final = (kind == "seller")
  -- AH mail lasts 30 days, so daysLeft tells when it arrived.
  local arrived = daysLeft and (now - math.floor((30 - daysLeft) * 86400)) or now
  local got = (money and money > 0) and money or (bid and ((bid or 0) + (deposit or 0) - (cut or 0))) or nil
  local rec
  for _, e in ipairs(list) do
    if not claimed[e] and not e.kind and e.n == name and e.mail and (e.bid == bid or not bid or not e.bid) and (e.buyer == buyer or not buyer)
       and math.abs((e.mt or 0) - arrived) < MATCH_WINDOW + 3600 and (e.got == got or e.pending or not e.got or not got) then
      rec = e; break
    end
  end
  if not rec then
    -- a sale seen on your Auctions tab so far (the oldest unmatched one first)
    for j = #list, 1, -1 do
      local e = list[j]
      if not claimed[e] and not e.kind and e.n == name and not e.mail and e.t and e.t <= arrived + 3600 and arrived - e.t < MATCH_WINDOW
         and (not e.bid or not bid or e.bid == bid or e.bid * (e.q or 1) == bid) then
        rec = e; break
      end
    end
  end
  local changed = false
  if rec then claimed[rec] = true end
  if not rec then
    rec = { n = name, t = final and (arrived - 3600) or arrived } -- final mail comes ~1h after the sale
    table.insert(list, rec)
    claimed[rec] = true
    changed = true
  end
  if final and rec.pending then changed = true end
  rec.mail, rec.mt = true, rec.mt or arrived
  rec.pending = not final
  rec.id = rec.id or IdFor(name)
  rec.bid = bid or rec.bid
  rec.buyout = buyout or rec.buyout
  rec.buyer = buyer or rec.buyer
  rec.dep, rec.cut = deposit or rec.dep, cut or rec.cut
  rec.got = got or rec.got
  if type(count) == "number" and count > 0 then rec.q = count end
  rec.ah = WhichAH(sender, bid, cut) or rec.ah
  return changed
end

---------------------------------------------------------------------------
-- The moment it happens: "A buyer has been found for your auction of X." /
-- "Your auction of X has expired." The modern AH client doesn't send these as
-- system chat: it fires AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION (with the
-- auction's ID) and AUCTION_HOUSE_SHOW_NOTIFICATION, anywhere in the world.
-- All three are listened to; whichever comes first is kept. The price, stack
-- and AH come from your saved auctions; the mail fills in cut and net later
-- and is merged into the same line.
---------------------------------------------------------------------------
local CHAT_SOLD = SubjectPattern(ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s.")
local CHAT_EXPIRED = SubjectPattern(ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.")
local function PlainName(s)
  if type(s) ~= "string" then return nil end
  s = s:match("%[(.-)%]") or s
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local base = s:match("^(.-) x%d+$") or s:match("^(.-) %(%d+%)$")
  return base or s
end

-- kind: nil (sold) or "expired"; aid when the game says which auction;
-- src: which event told us (the same sale comes once per event type)
local recent = {}
function S.Record(kind, name, aid, src)
  name = PlainName(name)
  if not name and not aid then return end
  local now = GetTime and GetTime() or time()
  -- the same event can come by notification and by chat
  for i = #recent, 1, -1 do
    local r = recent[i]
    if now - r.at > 20 then table.remove(recent, i)
    elseif r.kind == kind and ((aid and r.aid == aid) or (name and r.n == name and r.src ~= src and not (aid and r.aid))) then
      return
    end
  end
  recent[#recent + 1] = { at = now, kind = kind, n = name, aid = aid, src = src }
  -- which of your listings: by auction ID, else same name, ending soonest
  local best, bestAH
  for ah, snap in pairs(S.Auctions()) do
    for _, a in ipairs(snap.list or {}) do
      if aid and a.aid == aid then best, bestAH = a, ah break end
      if not aid and name and a.n == name and not a.sold and not a.chatDone
         and (not best or (a.exp or math.huge) < (best.exp or math.huge)) then
        best, bestAH = a, ah
      end
    end
    if aid and best then break end
  end
  name = name or (best and best.n)
  if not name then return end
  if best then best.chatDone = kind or "sold"; if not kind then best.sold = true end end
  local list = S.List()
  -- already known (Auctions tab, or an earlier message for this auction)?
  if aid then
    for _, e in ipairs(list) do if e.aid == aid and (e.kind == kind) then return end end
  end
  local t = time()
  local rec = { n = name, id = best and best.id or IdFor(name), q = best and best.q, t = t, ah = (best and bestAH) or AHNow(),
                chat = true, aid = aid or (best and best.aid) }
  if kind then
    rec.kind, rec.mt = kind, t
  else
    rec.bid = best and (best.buyout or best.bid)
    rec.pending = true -- gold comes by mail ~1h later
  end
  table.insert(list, 1, rec)
  Sort(list)
  Changed()
  return true
end

function S.OnSystemMessage(msg)
  if type(msg) ~= "string" then return end
  local name = msg:match(CHAT_SOLD)
  if name then return S.Record(nil, name, nil, "chat") end
  name = msg:match(CHAT_EXPIRED)
  if name then return S.Record("expired", name, nil, "chat") end
end

-- AUCTION_HOUSE_SHOW_(FORMATTED_)NOTIFICATION: (notification, text or item, auctionID)
function S.OnNotification(note, text, aid, src)
  local E = Enum and Enum.AuctionHouseNotification
  local SOLD = E and E.AuctionSold or 4
  local EXPIRED = E and E.AuctionExpired or 5
  if note ~= SOLD and note ~= EXPIRED then return end
  local kind = (note == EXPIRED) and "expired" or nil
  local name = type(text) == "string" and (text:match(CHAT_SOLD) or text:match(CHAT_EXPIRED) or text) or nil
  return S.Record(kind, name, type(aid) == "number" and aid or nil, src)
end

local function ReadInbox()
  local n = try(GetInboxNumItems) or 0
  if n == 0 then return end
  local list = S.List()
  local now, added, claimed = time(), false, {}
  for i = 1, n do
    local ok, ch = pcall(ReadOne, i, list, now, claimed)
    if ok and ch then added = true end
    if not ok and AskAHDB.debug then ns.Print("sales mail error: " .. tostring(ch)) end
  end
  if added then Sort(list); Changed() end
end

-- Read a mail just before its gold is taken (the mail may vanish after).
local function PreHook(fname)
  local orig = _G[fname]
  if type(orig) ~= "function" then return end
  _G[fname] = function(i, ...)
    if AskAHDB and type(i) == "number" then
      local list = S.List()
      local ok, ch = pcall(ReadOne, i, list, time())
      if ok and ch then Sort(list); Changed() end
    end
    return orig(i, ...)
  end
end
PreHook("TakeInboxMoney")
PreHook("AutoLootMailItem")
PreHook("DeleteInboxItem")
PreHook("TakeInboxItem")

-- /askah sales debug: what the mailbox and Auctions tab look like to AskAH.
function S.Debug()
  local P = ns.Print
  P(("sales debug: %d sales saved for %s."):format(#S.List(), UnitName("player") or "?"))
  local n, total = try(GetInboxNumItems)
  if not n then P("mailbox: open a mailbox first.") else
    P(("mailbox: %d mails loaded (%s on the server)."):format(n, tostring(total)))
    for i = 1, math.min(n, 15) do
      local _, _, sender, subject, money, _, daysLeft = try(GetInboxHeaderInfo, i)
      local kind, name, buyer, bid, _, deposit, cut = try(GetInboxInvoiceInfo, i)
      print(("   %d. %s | %s | money %s | %.1f days | invoice: %s %s buyer %s bid %s dep %s cut %s"):format(
        i, tostring(sender), tostring(subject), tostring(money), daysLeft or -1, tostring(kind), tostring(name),
        tostring(buyer), tostring(bid), tostring(deposit), tostring(cut)))
    end
  end
  local AH = C_AuctionHouse
  if AH and AH.GetNumOwnedAuctions then
    local c, sold = try(AH.GetNumOwnedAuctions) or 0, 0
    for i = 1, c do local o = try(AH.GetOwnedAuctionInfo, i); if o and o.status == 1 then sold = sold + 1 end end
    P(("auctions tab: %d of your auctions listed, %d marked sold (open the Auctions tab at the AH to refresh)."):format(c, sold))
  end
  print("   subject patterns: " .. SOLD_SUBJECT .. "  /  " .. PENDING_SUBJECT)
  S.DebugAuctions()
end

-- /askah auctions debug: which AH functions this client has, and what's saved.
function S.DebugAuctions()
  local P = ns.Print
  local AH = C_AuctionHouse
  P(("auctions debug: modern AH %s (owned list %s), classic AH %s (owner list %s). AH open: %s."):format(
    AH and "yes" or "no", tostring(AH and try(AH.GetNumOwnedAuctions)),
    GetOwnerAuctionItems and "yes" or "no", tostring(try(GetNumAuctionItems, "owner")), tostring(S.ahOpen or false)))
  local chars = 0
  for key, c in pairs(AskAHDB and AskAHDB.chars or {}) do
    for ah, snap in pairs(c.auctions or {}) do
      chars = chars + 1
      local ids = 0
      for _, a in ipairs(snap.list or {}) do if a.aid then ids = ids + 1 end end
      print(("   %s, %s AH: %d listed (%d with auction IDs), saved %s via %s"):format(key, ah, #(snap.list or {}), ids,
        ns.Data.Ago(snap.t), tostring(snap.api or "?")))
    end
  end
  if chars == 0 then print("   nothing saved yet: open the AH (AskAH asks for your auctions itself), then /reload so it's written to disk.") end
  local m = type(AskAHFeed) == "table" and AskAHFeed.mine
  local n = 0
  for _ in pairs(m or {}) do n = n + 1 end
  print(("   Blizzard feed is following %d of your auctions."):format(n))
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local function AHLabel(ah)
  if ah == "neutral" then return ORANGE .. "neutral AH|r" end
  if ah == "faction" then return BLUE .. "faction AH|r" end
  return GREY .. "AH ?|r"
end

local function When(t)
  if not t then return "?" end
  local d = time() - t
  if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
  if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
  return date("%b %d", t)
end
S.When = When

function S.Totals()
  local now = time()
  local day, week, dayN, weekN, unpriced, unsold = 0, 0, 0, 0, 0, 0
  for _, e in ipairs(S.List()) do
    local age = now - (e.t or 0)
    if e.kind then
      if age < 7 * 86400 then unsold = unsold + 1 end
    elseif age < 7 * 86400 then
      weekN = weekN + 1
      week = week + (e.got or 0)
      if not e.got then unpriced = unpriced + 1 end
      if age < 86400 then dayN = dayN + 1; day = day + (e.got or 0) end
    end
  end
  return dayN, day, weekN, week, unpriced, unsold
end

-- filter: "sold", "unsold" or nil/"all"
-- The deposit for an auction that expired: what you really paid when AskAH
-- saw you post it (saved with its sell prediction), else an estimate.
local function DepositFor(e)
  if not e.id then return nil end
  local w = (e.ah == "neutral") and "neutral" or "faction"
  for _, pr in ipairs(AskAHDB.preds or {}) do
    if pr.id == e.id and pr.ah == w and pr.t <= (e.t or 0) + 300 and (e.t or 0) - pr.t < 3 * 86400 and pr.dep then
      return pr.dep, pr.depReal
    end
  end
  local v = ns.Sell and ns.Sell.Vendor and ns.Sell.Vendor(e.id) or 0
  if v > 0 then return math.floor(v * (e.q or 1) * (w == "neutral" and 0.15 or 0.05)), false end
end

local function Filtered(filter)
  local out = {}
  for _, e in ipairs(S.List()) do
    if filter == "sold" and not e.kind or filter == "unsold" and e.kind or filter ~= "sold" and filter ~= "unsold" then
      out[#out + 1] = e
    end
  end
  -- auctions the Blizzard feed saw sell that no message or mail has
  -- confirmed yet: shown as "probably sold" (not counted in the totals)
  -- and ones whose time ran out (or the feed saw expire) with no mail yet
  if S.ActiveRows then
    local ok, rows = pcall(S.ActiveRows)
    for _, r in ipairs(ok and rows or {}) do
      if r.done == "sold?" and not r.char and filter ~= "unsold" then
        out[#out + 1] = { n = r.n, id = r.id, q = r.q, bid = r.buyout or r.bid, t = r.doneT, ah = r.ah, probable = true, aid = r.aid }
      elseif r.done == "expired?" and not r.char and filter ~= "sold" then
        out[#out + 1] = { kind = "expired", n = r.n, id = r.id, q = r.q, t = r.doneT, ah = r.ah, probableExp = true,
                          timedOut = r.timedOut, aid = r.aid }
      end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  end
  return out
end
S.Filtered = Filtered

local function UnsoldText(e)
  return (e.kind == "cancelled" and (ORANGE .. "cancelled|r") or ("|cffff4040" .. "didn't sell|r"))
end

-- What it goes for now at that AH, from AskAH's scans (to help relist).
local function NowPrice(e)
  if not e.id then return nil end
  local p = ns.Data.Prices(e.ah == "neutral" and "neutral" or "faction")[e.id]
  return p and p.p
end

function S.PrintChat(n, filter)
  local list = Filtered(filter)
  n = n or 10
  if filter == "unsold" then
    if #list == 0 then ns.Print("no expired or cancelled auctions recorded. AskAH sees them from the \"Auction expired\" mail when you open a mailbox.") return end
    ns.Print("your auctions that didn't sell (newest first):")
    for i = 1, math.min(n, #list) do
      local e = list[i]
      local link = e.id and select(2, try(GII, e.id))
      local now = NowPrice(e)
      print(("   %s  %s%s  %s  %s%s"):format(GREY .. When(e.t) .. "|r", link or (YELLOW .. e.n .. "|r"),
        (e.q and e.q > 1) and (" x" .. e.q) or "", UnsoldText(e), AHLabel(e.ah),
        now and (GREY .. "  now " .. "|r" .. Coins(now) .. GREY .. " each|r") or ""))
    end
    if #list > n then print(("   ...%d more: /askah sales"):format(#list - n)) end
    return
  end
  if #list == 0 then
    ns.Print("no sales recorded yet. AskAH reads them from your AH sale mail when you open a mailbox (mail from the last 30 days counts), and from your Auctions tab at the AH.")
    return
  end
  local dayN, day, weekN, week = S.Totals()
  ns.Print(("your latest AH sales (today: %d for %s, last 7 days: %d for %s):"):format(dayN, Coins(day), weekN, Coins(week)))
  if filter ~= "sold" then print("   (lines marked didn't sell came back by mail; /askah sales unsold lists only those)") end
  for i = 1, math.min(n, #list) do
    local e = list[i]
    local name = e.n
    local link = e.id and select(2, try(GII, e.id))
    local price = e.kind and UnsoldText(e) or e.got and (Coins(e.got) .. GREY .. " net|r") or (e.bid and (Coins(e.bid) .. GREY .. " (before cut)|r") or (GREY .. "price when the mail arrives|r"))
    print(("   %s  %s%s  %s  %s"):format(GREY .. When(e.t) .. "|r", link or (YELLOW .. name .. "|r"),
      (e.q and e.q > 1) and (" x" .. e.q) or "", price, AHLabel(e.ah)))
  end
  if #list > n then print(("   ...%d more: /askah sales"):format(#list - n)) end
end

function S.Clear()
  ns.Data.Char().sales = {}
  Changed()
  ns.Print("cleared this character's sales list.")
end

---------------------------------------------------------------------------
-- Window (same look as the deals window)
---------------------------------------------------------------------------
local win, scroll, child
local rows = {}
local ICON, ROW_H = 26, 40
local COLW = { 46, 84, 84, 70 } -- Qty, Sold for, You got, When
local COLS = { "Qty", "Sold for", "You got", "When" }

local function Tex(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
  return t
end

local function Font(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function MakeCols(f, template, point, y)
  f.cols = {}
  local right = -6
  for i = #COLW, 1, -1 do
    local fs = Font(f, template, "RIGHT")
    fs:SetWidth(COLW[i] - 6)
    fs:SetPoint(point, f, point, right, y)
    fs:SetWordWrap(false)
    f.cols[i] = fs
    right = right - COLW[i]
  end
  return -right
end

local function RowTooltip(self)
  local e = self.e
  if not e then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if e.id then pcall(GameTooltip.SetItemByID, GameTooltip, e.id) else GameTooltip:AddLine(e.n, 1, 1, 1) end
  GameTooltip:AddLine(" ")
  if e.active then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("AskAH: your auction", 0.2, 0.8, 1)
    GameTooltip:AddDoubleLine("Where", AHLabel(e.ah), 0.7, 0.7, 0.7, 1, 1, 1)
    if e.q then GameTooltip:AddDoubleLine("How many", tostring(e.q), 0.7, 0.7, 0.7, 1, 1, 1) end
    if e.buyout then GameTooltip:AddDoubleLine("Buyout", Coins(e.buyout) .. ((e.q or 1) > 1 and ("  (" .. Coins(e.buyout / e.q) .. " each)") or ""), 0.7, 0.7, 0.7, 1, 1, 1) end
    if e.bid then GameTooltip:AddDoubleLine("Current bid", Coins(e.bid), 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:AddDoubleLine("Time left", LeftText(e), 0.7, 0.7, 0.7, 1, 1, 1)
    local now = NowPrice(e)
    if now then GameTooltip:AddDoubleLine("Lowest there (last scan)", Coins(now) .. " each", 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:AddLine("As of your last visit to that AH (" .. ns.Data.Ago(e.seen) .. "). Sold / expired is updated from your mail.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
    return
  end
  if e.kind then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(e.kind == "cancelled" and "AskAH: you cancelled this auction" or "AskAH: this auction didn't sell", 1, 0.4, 0.3)
    GameTooltip:AddDoubleLine("Came back", e.t and date("%a %b %d, %H:%M", e.t) or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Where", AHLabel(e.ah), 0.7, 0.7, 0.7, 1, 1, 1)
    if e.q then GameTooltip:AddDoubleLine("How many", tostring(e.q), 0.7, 0.7, 0.7, 1, 1, 1) end
    local now = NowPrice(e)
    if now then GameTooltip:AddDoubleLine("Lowest there now", Coins(now) .. " each", 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:AddLine("The item came back by mail. The deposit isn't refunded when an auction expires.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
    return
  end
  GameTooltip:AddLine("AskAH: your sale", 0.2, 0.8, 1)
  GameTooltip:AddDoubleLine("Sold", e.t and date("%a %b %d, %H:%M", e.t) or "?", 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("Where", AHLabel(e.ah), 0.7, 0.7, 0.7, 1, 1, 1)
  if e.buyer and e.buyer ~= "" then GameTooltip:AddDoubleLine("Buyer", e.buyer, 0.7, 0.7, 0.7, 1, 1, 1) end
  if e.bid then GameTooltip:AddDoubleLine("Sold for", Coins(e.bid), 0.7, 0.7, 0.7, 1, 1, 1) end
  if e.buyout and e.buyout > 0 and e.buyout ~= e.bid then
    GameTooltip:AddDoubleLine("Your buyout", Coins(e.buyout), 0.7, 0.7, 0.7, 1, 1, 1)
  end
  if e.cut then GameTooltip:AddDoubleLine("AH cut", "-" .. Coins(e.cut), 0.7, 0.7, 0.7, 1, 0.5, 0.5) end
  if e.dep and e.dep > 0 then GameTooltip:AddDoubleLine("Deposit back", "+" .. Coins(e.dep), 0.7, 0.7, 0.7, 0.5, 1, 0.5) end
  if e.got then GameTooltip:AddDoubleLine("You got", Coins(e.got), 0.7, 0.7, 0.7, 0.3, 1, 0.3) end
  if e.pending then GameTooltip:AddLine("The gold is still on its way (Sale Pending mail).", 0.8, 0.8, 0.8, true) end
  if not e.mail then GameTooltip:AddLine("Seen as Sold on your Auctions tab. The full breakdown shows once the AH mail arrives and you open a mailbox.", 0.8, 0.8, 0.8, true) end
  GameTooltip:Show()
end

local function NewRow()
  local b = CreateFrame("Button", nil, child)
  b.bg = Tex(b, "BACKGROUND", 1, 1, 1, 0.035)
  b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("TOPLEFT", 8, -4)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local colsW = MakeCols(b, "GameFontHighlightSmall", "TOPRIGHT", -8)
  b.name = Font(b, "GameFontHighlight")
  b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -1)
  b.name:SetPoint("RIGHT", b, "RIGHT", -colsW - 6, 0)
  b.name:SetWordWrap(false)
  b.detail = Font(b, "GameFontDisableSmall")
  b.detail:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
  b.detail:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.detail:SetWordWrap(false)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnEnter", RowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function S.Refresh()
  if not win or not win:IsShown() then return end
  local filter = AskAHDB.salesFilter or "all"
  local active = (filter == "active")
  local list = active and S.ActiveRows() or Filtered(filter)
  for k, b in pairs(win.filters) do
    if k == filter then b:LockHighlight() else b:UnlockHighlight() end
  end
  local heads = active and { "Qty", "Buyout", "Bid", "Time left" } or COLS
  for i, l in ipairs(heads) do win.head.cols[i]:SetText(l) end
  win.headItem:SetText(active and "Item (ending soonest first)" or "Item (newest first)")
  win.title:SetText(active and "AskAH |cffffffffMy auctions|r" or "AskAH |cffffffffMy sales|r")
  local dayN, day, weekN, week, unpriced, unsold = S.Totals()
  if active then
    local up, value, seen = 0, 0, {}
    for _, r in ipairs(list) do
      if not r.done then up = up + 1; value = value + (r.buyout or r.bid or 0) end
    end
    for ah, snap in pairs(S.Auctions()) do
      seen[#seen + 1] = (ah == "neutral" and "neutral" or "faction") .. " AH " .. ns.Data.Ago(snap.t)
    end
    local alts = 0
    for _, r in ipairs(list) do if r.char and not r.done then alts = alts + 1 end end
    if alts > 0 then seen[#seen + 1] = ("%d on your other characters"):format(alts) end
    win.status:SetText(("%d up, worth %s at your buyouts    seen: %s"):format(up, Coins(value),
      #seen > 0 and table.concat(seen, ", ") or "never"))
  else win.status:SetText(("Today: %d sold, %s    Last 7 days: %d sold, %s    %d didn't sell%s"):format(
    dayN, Coins(day), weekN, Coins(week), unsold,
    unpriced > 0 and ("    " .. unpriced .. " waiting for mail") or "")) end
  local w = scroll:GetWidth()
  if not w or w < 100 then w = win:GetWidth() - 40 end
  child:SetWidth(w)
  for _, r in ipairs(rows) do r:Hide() end
  win.empty:SetShown(#list == 0)
  if #list == 0 and active then
    win.empty:SetText("No auctions saved yet.\n\nVisit the auction house once: AskAH reads your auctions there (and again whenever you post or cancel), then you can see them here from anywhere.")
  elseif #list == 0 and filter == "unsold" then
    win.empty:SetText("Nothing here yet.\n\nAuctions that expire (or that you cancel) come back by mail. AskAH records them when you open a mailbox, including ones still in your inbox.")
  elseif #list == 0 then
    win.empty:SetText(win.emptyText)
  end
  local y = 0
  for i, e in ipairs(list) do
    local b = rows[i] or NewRow()
    rows[i] = b
    b.e = e
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    b:SetSize(w, ROW_H)
    b.bg:SetAlpha((i % 2 == 0) and 1 or 0.4)
    local _, _, quality, _, _, _, _, _, _, icon = try(GII, e.id or e.n)
    if not icon and e.id then icon = try(C_Item and C_Item.GetItemIconByID, e.id) or try(GetItemIcon, e.id) end
    b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local col = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    b.name:SetText(e.n or "?")
    if col then b.name:SetTextColor(col.r, col.g, col.b) else b.name:SetTextColor(1, 1, 1) end
    b.cols[1]:SetText(e.q and tostring(e.q) or GREY .. "-|r")
    b.cols[4]:SetText(GREY .. When(e.t) .. "|r")
    local bits = { AHLabel(e.ah) }
    if e.char then bits[#bits + 1] = BLUE .. e.char .. "|r" end
    if e.active and e.posted and not e.done then bits[#bits + 1] = YELLOW .. "just posted|r" end
    if e.active then
      b.cols[2]:SetText(e.buyout and Coins(e.buyout) or GREY .. "none|r")
      b.cols[3]:SetText(e.bid and Coins(e.bid) or (e.minBid and (GREY .. Coins(e.minBid) .. "|r")) or GREY .. "-|r")
      b.cols[4]:SetText(LeftText(e))
      if e.done == "sold?" or e.done == "expired?" or e.done == "ended?" then
        bits[#bits + 1] = LeftText(e) .. (e.doneT and (" " .. When(e.doneT)) or "") .. GREY ..
          (e.timedOut and " (its time ran out; your mail confirms)|r" or " (Blizzard feed; your mail confirms)|r")
      elseif e.done == "sold" then
        bits[#bits + 1] = "|cff33ff33sold|r" .. (e.doneT and (" " .. When(e.doneT)) or "")
        b.bg:SetVertexColor(0.3, 1, 0.3)
      elseif e.done then
        bits[#bits + 1] = (e.done == "cancelled" and "cancelled" or "expired, came back by mail") .. (e.doneT and (" " .. When(e.doneT)) or "")
        b.bg:SetVertexColor(1, 0.35, 0.3)
      else
        if e.bidder and e.bidder ~= "" then bits[#bits + 1] = "high bid from " .. e.bidder end
        local ch = S.Chance(e)
        if ch then
          local col = ch >= 0.7 and GREEN or (ch >= 0.35 and YELLOW or "|cffff4040")
          bits[#bits + 1] = col .. math.floor(ch * 100 + 0.5) .. "% chance to sell|r"
        end
        local a = e.api
        if e.partial then bits[#bits + 1] = GREEN .. e.partial .. " of the stack sold|r" end
        if a and a.ahead and a.low and a.unit then
          if a.ahead > 0 then
            bits[#bits + 1] = YELLOW .. ("undercut: %d cheaper ahead of you, lowest |r%s" .. YELLOW .. " each|r"):format(a.ahead, Coins(a.low))
          else
            bits[#bits + 1] = GREEN .. "cheapest listed|r"
          end
          bits[#bits + 1] = "Blizzard " .. ns.Data.Ago(a.t)
        else
          local now = NowPrice(e)
          if now and e.buyout and e.q and e.q > 0 and now < e.buyout / e.q then
            bits[#bits + 1] = YELLOW .. "undercut: lowest " .. "|r" .. Coins(now) .. YELLOW .. " each|r"
          end
        end
        b.bg:SetVertexColor(1, 1, 1)
      end
      bits[#bits + 1] = "as of " .. ns.Data.Ago(e.seen)
    elseif e.kind then
      b.cols[2]:SetText(UnsoldText(e))
      b.cols[3]:SetText(GREY .. "-|r")
      bits[#bits + 1] = e.mail and "item came back by mail"
        or (e.probableExp and (e.timedOut and "probably expired: its time ran out, item on its way by mail" or "probably expired (Blizzard feed), item on its way by mail"))
        or "expired (game message), item on its way by mail"
      local dep, real = DepositFor(e)
      if dep and dep > 0 then bits[#bits + 1] = "|cffff6060" .. (real and "deposit lost " or "deposit lost ~") .. "|r" .. Coins(dep) end
      local now = NowPrice(e)
      if now then bits[#bits + 1] = "lowest there now " .. Coins(now) .. " each" end
      b.bg:SetVertexColor(1, 0.35, 0.3)
    elseif e.probable then
      b.cols[2]:SetText(e.bid and (GREY .. Coins(e.bid) .. "|r") or GREY .. "?|r")
      b.cols[3]:SetText(GREY .. "?|r")
      b.bg:SetVertexColor(0.6, 0.9, 0.6)
      bits[#bits + 1] = "|cff33ff33probably sold|r " .. GREY .. "(Blizzard feed saw it go with hours left; the mail confirms, a cancel looks the same)|r"
    else
      b.cols[2]:SetText(e.bid and Coins(e.bid) or GREY .. "?|r")
      b.cols[3]:SetText(e.got and Coins(e.got) or GREY .. "?|r")
      b.bg:SetVertexColor(1, 1, 1)
      if e.buyer and e.buyer ~= "" then bits[#bits + 1] = "to " .. e.buyer end
      if e.pending then bits[#bits + 1] = YELLOW .. "gold on its way|r"
      elseif not e.mail then bits[#bits + 1] = "cut and net come with the AH mail" end
      if e.cut and e.cut > 0 then bits[#bits + 1] = "cut " .. Coins(e.cut) end
    end
    -- where AskAH heard about it
    local src = {}
    if e.chat then src[#src + 1] = "message" end
    if e.mail then src[#src + 1] = "mail" end
    if e.aid and not e.active then src[#src + 1] = "Auctions tab" end
    if e.probable then src[#src + 1] = "Blizzard feed" end
    if #src > 0 and not e.active then bits[#bits + 1] = GREY .. "from " .. table.concat(src, " + ") .. "|r" end
    b.detail:SetText(table.concat(bits, GREY .. "  ·  |r"))
    b:Show()
    y = y + ROW_H + 2
  end
  child:SetHeight(y + 8)
end

local function Create()
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  win = CreateFrame("Frame", "AskAHSalesWindow", UIParent, tmpl)
  local size = AskAHDB and AskAHDB.salesSize
  win:SetSize(size and size[1] or 560, size and size[2] or 440)
  win:SetPoint("CENTER")
  win:SetMovable(true)
  win:SetResizable(true)
  if win.SetResizeBounds then win:SetResizeBounds(460, 240, 1000, 1000)
  elseif win.SetMinResize then win:SetMinResize(460, 240); if win.SetMaxResize then win:SetMaxResize(1000, 1000) end end
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)

  if win.SetBackdrop then
    win:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    win:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    win:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
  else
    Tex(win, "BACKGROUND", 0.05, 0.05, 0.07, 0.95):SetAllPoints()
  end

  local bar = Tex(win, "BORDER", 1, 1, 1, 0.06)
  bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("TOPRIGHT", -4, -4); bar:SetHeight(48)
  local title = Font(win, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("AskAH |cffffffffMy sales|r")
  win.title = title
  win.status = Font(win, "GameFontDisableSmall")
  win.status:SetPoint("TOPLEFT", 14, -32)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- All / Sold / Didn't sell
  win.filters = {}
  local prevBtn
  for _, f in ipairs({ { "unsold", "Didn't sell", 84 }, { "sold", "Sold", 56 }, { "all", "All", 46 }, { "active", "Up now", 66 } }) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(f[3], 20)
    if prevBtn then b:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -34, -8) end
    b:SetText(f[2])
    b:SetScript("OnClick", function()
      AskAHDB.salesFilter = (f[1] ~= "all") and f[1] or nil
      if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
      S.Refresh()
    end)
    win.filters[f[1]] = b
    prevBtn = b
  end

  local div = Tex(win, "BORDER", 1, 1, 1, 0.15)
  div:SetPoint("TOPLEFT", 4, -52); div:SetPoint("TOPRIGHT", -4, -52); div:SetHeight(1)

  -- column headings
  local head = CreateFrame("Frame", nil, win)
  head:SetPoint("TOPLEFT", 6, -54); head:SetPoint("TOPRIGHT", -28, -54); head:SetHeight(18)
  MakeCols(head, "GameFontDisableSmall", "RIGHT", 0)
  for i, l in ipairs(COLS) do head.cols[i]:SetText(l) end
  local item = Font(head, "GameFontDisableSmall")
  item:SetPoint("LEFT", 8, 0)
  item:SetText("Item (newest first)")
  win.head, win.headItem = head, item

  local foot = Font(win, "GameFontDisableSmall")
  foot:SetPoint("BOTTOMLEFT", 14, 9)
  foot:SetPoint("RIGHT", win, "RIGHT", -30, 0)
  foot:SetWordWrap(false)
  foot:SetText("From your AH sale mail (open a mailbox) and your Auctions tab. Hover a line for details.")
  local fdiv = Tex(win, "BORDER", 1, 1, 1, 0.15)
  fdiv:SetPoint("BOTTOMLEFT", 4, 26); fdiv:SetPoint("BOTTOMRIGHT", -4, 26); fdiv:SetHeight(1)

  scroll = CreateFrame("ScrollFrame", "AskAHSalesScroll", win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -74)
  scroll:SetPoint("BOTTOMRIGHT", -28, 30)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(520, 1)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w); S.Refresh() end end)

  win.empty = Font(win, "GameFontHighlight", "CENTER")
  win.empty:SetPoint("TOPLEFT", 30, -110); win.empty:SetPoint("TOPRIGHT", -30, -110)
  win.emptyText = "No sales recorded yet.\n\nOpen a mailbox: AskAH reads your auction house sale mail, including old sale mail still in your inbox (it stays 30 days). Sold auctions on your Auctions tab at the AH are added too."
  win.empty:SetText(win.emptyText)

  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    win:StopMovingOrSizing()
    if AskAHDB then AskAHDB.salesSize = { math.floor(win:GetWidth()), math.floor(win:GetHeight()) } end
    S.Refresh()
  end)

  win:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  win:SetScript("OnEvent", function()
    if win.queued then return end
    win.queued = true
    local function go() win.queued = false; S.Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, go) else go() end
  end)
  -- keep it current while it's open: time left counts down, auctions whose
  -- time ran out move to "probably expired"
  local acc = 0
  win:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc >= 30 then acc = 0; pcall(S.Refresh) end
  end)
  tinsert(UISpecialFrames, "AskAHSalesWindow")
end

function S.Show()
  if not win then Create() end
  win:Show()
  S.Refresh()
end
function S.Hide() if win then win:Hide() end end
function S.Toggle() if win and win:IsShown() then S.Hide() else S.Show() end end
-- open on a given view: "active", "all", "sold", "unsold"
function S.ShowView(v)
  AskAHDB.salesFilter = (v ~= "all") and v or nil
  S.Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Your auction IDs as the hourly feed last saw them (AskAHFeed.mine, written
-- by Feed\AskAHFeed.ps1): { status = up|sold|expired|ended, t, q0, qNow, id }
function S.FeedStatus(aid)
  local m = aid and type(AskAHFeed) == "table" and AskAHFeed.mine and AskAHFeed.mine[aid]
  if not m then return nil end
  local st, t, q0, qn, iid = m:match("^(%a+),(%d+),(%d+),(%d+),(%d*)")
  if not st then return nil end
  local _, _, _, _, _, _, tl, unit, ahead, low = strsplit(",", m)
  return { status = st, t = tonumber(t), q0 = tonumber(q0), qNow = tonumber(qn), id = tonumber(iid),
           tl = tonumber(tl), unit = tonumber(unit), ahead = tonumber(ahead), low = tonumber(low) }
end

-- A listing saved without its auction ID (classic-style AH): the feed matches
-- it by item, stack size and buyout, and keeps the auction ID it found under
-- AskAHFeed.mineKey["item,qty,unit"].
function S.FeedMatch(a)
  local k = type(AskAHFeed) == "table" and AskAHFeed.mineKey
  if not (k and a.id and a.q and a.buyout and a.q > 0) then return nil end
  local aid = k[("%d,%d,%d"):format(a.id, a.q, math.floor(a.buyout / a.q))]
  return aid and S.FeedStatus(aid)
end

-- At login: which of your auctions the feed thinks sold since you last looked.
function S.FeedNews()
  if not (type(AskAHFeed) == "table" and AskAHFeed.mine) then return end
  local since = AskAHDB.feedNewsT or 0
  local soldN, soldValue, names, expiredN, newest = 0, 0, {}, 0, since
  for _, r in ipairs(S.ActiveRows()) do
    if r.feed and r.doneT and r.doneT > since then
      if r.done == "sold?" then
        soldN = soldN + 1
        soldValue = soldValue + (r.buyout or r.bid or 0)
        if #names < 4 then names[#names + 1] = r.n end
      elseif r.done == "expired?" then expiredN = expiredN + 1 end
      if r.doneT > newest then newest = r.doneT end
    end
  end
  AskAHDB.feedNewsT = newest
  if soldN == 0 and expiredN == 0 then return end
  local msg = ("%d of your auctions probably sold"):format(soldN)
  if soldN > 0 then msg = msg .. (" (~%s before the cut): %s%s"):format(Coins(soldValue), table.concat(names, ", "), soldN > #names and ", ..." or "") end
  if expiredN > 0 then msg = msg .. ("; %d probably expired"):format(expiredN) end
  ns.Print(msg .. ". /askah auctions for the list; your mailbox confirms.")
end

local news = CreateFrame("Frame")
news:RegisterEvent("PLAYER_ENTERING_WORLD")
news:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  if C_Timer and C_Timer.After then C_Timer.After(6, function() pcall(S.FeedNews) end) end
end)

local ev = CreateFrame("Frame")
-- Some of these only exist on some clients (AUCTION_OWNED_LIST_UPDATE is classic
-- only); an unknown event throws, so register each one safely.
for _, e in ipairs({
  "OWNED_AUCTIONS_UPDATED",
  "AUCTION_OWNED_LIST_UPDATE",
  "AUCTION_HOUSE_SHOW",
  "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_CANCELED",
  "AUCTION_HOUSE_CLOSED",
  "PLAYER_MONEY",
  "CHAT_MSG_SYSTEM",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "MAIL_INBOX_UPDATE",
  "MAIL_SHOW",
  "AUCTION_HOUSE_SHOW_NOTIFICATION",
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
}) do pcall(ev.RegisterEvent, ev, e) end
-- while the AH is open, ask for your auctions every minute, so sold ones show
-- even if you just stand there
local ownedTicker
ev:SetScript("OnEvent", function(_, event, msg, a2, a3)
  if not AskAHDB then return end
  if event == "CHAT_MSG_SYSTEM" then pcall(S.OnSystemMessage, msg) return end
  if event == "AUCTION_HOUSE_SHOW_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
    local ok, err = pcall(S.OnNotification, msg, a2, a3, event)
    if not ok and AskAHDB.debug then ns.Print("auction notification error: " .. tostring(err)) end
    if AskAHDB.debug then ns.Print(("auction notification %s: %s %s %s"):format(event, tostring(msg), tostring(a2), tostring(a3))) end
    return
  end
  if event == "PLAYER_MONEY" then
    local m = GetMoney()
    local pd = S.pendingDep
    if pd and GetTime() - pd.at < 5 and pd.money and m < pd.money then
      local each = math.floor((pd.money - m) / #pd.preds)
      for _, pr in ipairs(pd.preds) do pr.dep, pr.depReal = each, true end
      S.pendingDep = nil
    end
    S.lastMoney = m
    return
  end
  if event == "OWNED_AUCTIONS_UPDATED" then
    S.gotOwned = true
    pcall(ReadOwned)
    pcall(SnapshotModern)
    Changed()
  elseif event == "AUCTION_OWNED_LIST_UPDATE" then
    S.gotOwned = true
    pcall(SnapshotClassic)
    Changed()
  elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_AUCTION_CREATED" or event == "AUCTION_CANCELED" then
    if event == "AUCTION_HOUSE_SHOW" then S.lastMoney = GetMoney() end
    -- refresh the list of your auctions a moment later (and again, in case
    -- the AH was still busy and dropped the first ask)
    if C_Timer and C_Timer.After then
      if event == "AUCTION_HOUSE_SHOW" then
        S.ahOpen = true
        for _, d in ipairs({ 1, 4, 10 }) do C_Timer.After(d, function() if S.ahOpen then QueryOwned() end end) end
        if C_Timer.NewTicker and not ownedTicker then
          ownedTicker = C_Timer.NewTicker(60, function() if S.ahOpen then QueryOwned() end end)
        end
      else
        C_Timer.After(0.5, QueryOwned); C_Timer.After(3, QueryOwned)
      end
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if S.ahOpen and not S.gotOwned then QueryOwned() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- last look at whatever the AH told us while it was open
    if S.ahOpen then pcall(SnapshotAny) end
    S.ahOpen, S.gotOwned = nil, nil
    if ownedTicker then ownedTicker:Cancel(); ownedTicker = nil end
    Changed()
  else
    pcall(ReadInbox)
    -- mail headers can arrive a moment after the mailbox opens
    if event == "MAIL_SHOW" and C_Timer and C_Timer.After then
      C_Timer.After(1, function() pcall(ReadInbox) end)
      C_Timer.After(3, function() pcall(ReadInbox) end)
    end
  end
end)
