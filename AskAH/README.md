# AskAH (WoW: Forever)

Hover any item and AskAH adds to the tooltip:
- **Auction house price** (last seen) and **vendor price**
- **Auction it / vendor it / keep it** advice (accounts for the 5% AH cut and soulbound items)
- For gear: **can you wear it** (level, armor type, class) and **is it an upgrade** over what you have on, scored for your spec, with the stat changes (e.g. `+10 Str, -44 Armor`)

The tooltip is kept short: the first AskAH line gives the verdict (auction it, vendor it, keep it), then one line per price and a line or two for gear, professions and crafting. Hold **Shift** for the detail (listing counts, data age, guide steps, set bonuses, each ring/trinket compared). Switch sections on or off, or always show the detail, in **Esc > Options > AddOns > AskAH** (`/askah options`), or `/askah tooltip full|compact`.

Spec is detected automatically (Warrior with a shield = Prot, 2H = Arms, else Fury). Override with `/askah spec prot|arms|fury|auto`.
Prot weights follow your Gemini chat: 1 Str ~ 1 Sta, 1 Sta ~ 16 Armor, main-hand DPS matters most, Defense nearly worthless, 2-handers flagged as not for Prot.

Also included: in-game Q&A guide, AH scanner, stats/bags/bank snapshots.

## Install
Copy the `AskAH` folder to `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.

## Commands
`/askah help` lists them grouped by topic. On/off switches are also in Esc > Options > AddOns > AskAH.
- `/askah` - open the window (search box + answers by topic)
- `/askah <words>` - print matching answers in chat, e.g. `/askah lucine`
- `/askah add Question? = Answer` - save your own entry
- `/askah mine` / `/askah remove <n>` - list / delete your entries
- `/askah ah on|off` - auto-open the guide next to the AH (off by default)
- `/askah tooltip on|off` - turn the tooltip info on/off
- `/askah spec <spec>` - which spec the upgrade check uses
- Opening the auction house scans it automatically (at most once per 15 min). `/askah autoscan on|off` to change.
- `/askah scan` - scan the whole auction house by hand
- The goblin (neutral) AH in Booty Bay / Gadgetzan / Everlook is scanned and stored separately; tooltips show both prices and which one pays more after cuts (5% faction, 15% neutral). `/askah ahtype neutral|faction|auto` if it guesses wrong. (stand at the AH; the server allows ~1 full scan per 15 min)
- `/askah sales` - your latest AH sales, newest first (see My sales below). `/askah sales chat` prints the last 10 in chat, `/askah sales unsold` lists auctions that didn't sell, `/askah sales clear` forgets them
- Minimap button (gold coin): left-click for a menu of everything AskAH does (sales, deals, scan, guide, stats, bags, prices), right-click for your sales, drag to move. `/askah minimap off|on` hides/shows it
- `/askah sales debug` - shows what your mailbox and Auctions tab look like to AskAH, if sales don't show up
- `/askah auctions` - your auctions that are up right now, from anywhere in the world (as of your last AH visit). `/askah auctions chat` lists them in chat, `/askah auctions debug` shows what AskAH can see of them
- `/askah price <item>` - last-seen price, e.g. `/askah price copper ore`
- `/askah stats` / `/askah bags` - open the Character / Bags tab
- `/askah worth` - value of your bags at AH prices
- Item tooltips get an "AH (AskAH)" price line once a price is known

## Live data it reads
- Auction house: full scan (C_AuctionHouse.ReplicateItems, or QueryAuctionItems getAll on classic-style clients) plus every search you do
- Character: level, health, primary stats, armor, attack power, defense, dodge/parry/block, block value, crit, gold, equipped gear
- Bags (incl. reagent bag) and bank (when you open it)

All of it is saved to `WTF\Account\<ACCOUNT>\SavedVariables\AskAH.lua` on /reload or logout.

## What an addon can't do
- Read the AH when you're not standing at it (no web/server access from addons)
- Make network calls or write files while you play
- Read some combat values during combat on the modern client (stats are read out of combat)

## Guide tab
The Guide tab shows only gold routes and leveling guides for the character you're on: gold farms for your level and professions, zones and dungeons for your level, your class's spec/talents/rotation/class quests, and the next steps for each of your professions (with AH cost of the mats). Content is in `Knowledge.lua` (sources listed at the top); edit it and `/reload`.

## Target client (from the Gemini brief)
- WoW: Forever, `## Interface: 16001` (modern client API, Lua 5.1)
- Use `C_*` namespaces; no combat-time automation; SavedVariables for storage
- If it shows as out of date: `/dump select(4, GetBuildInfo())` and update the .toc

## Professions
Tooltips say when an item is on a profession leveling path. Two WoW Forever guide sites are merged for each profession: wow-professions.com and Wowhead (Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, First Aid, Cooking; Mining's smelting steps from wow-professions.com). Only items those guides use are flagged. Raw materials count too (bars -> ore, bolts -> cloth, powders -> stone, cured hides -> hide + salt). For professions you have, it shows how many you still need from your current skill to 300 (the larger guide's count, with each site's number) and at which steps. Under that, "On the profession leveling guides" lists every profession whose guide uses the item, marked "yours" or "you're past this". Recipe items (Pattern:, Plans:, Schematic:, Formula:, Recipe:, Manual:) show whether the recipe they teach is a step on any of those guides: the profession, the skill range, about how many crafts, and which site uses it. They're marked "learn it now" or "keep it for skill N" when it's your profession and you haven't passed it yet, "past it", or "not your profession". `/askah guides [item]` checks that the guide data loaded and shows the skills AskAH read. Icy Veins' Forever guides couldn't be read, so they're not included. The guides are based on the Forever beta, so treat counts as estimates.

## Auction house deals window

When you open the auction house, a deals window pops up beside it. It is worked out from AskAH's own full scans. AskAH scans by itself when you open the AH, at most once every 15 minutes. Profit is counted after the AH cut (5% faction, 15% neutral) and an estimate of the deposit. A deal has to clear 20s profit and a 15% margin.

- **Sure profit:** listings cheaper than a vendor pays for the item. Buy them and sell them to a vendor.
- **Cheap vs the usual price:** listings at 70% or less of the item's usual price, a common flipping rule. The usual price is a running average of the scans' market price (the price at the cheapest quarter of the listed units). It only counts after 3 or more scans. Items that are suddenly flooded with listings and dropping are skipped.
- **Price gaps:** the cheapest few listings are far under the next ones, so you can buy them and relist just under the next price. It warns you when there is no price history yet.
- **Crafting profit:** your known recipes whose result sells here for more than the materials cost. Open each profession window once so AskAH learns what the recipes make.
- **Cheaper here than at the other AH:** faction vs neutral, using both AHs' recent scans.
- **Crazy prices:** items listed at 2x their usual price or more. It tells you if you have some in your bags or bank to sell.
- **Black Market note:** a note when Black Lotus or Arcane Crystal costs more than Mister Graphed's fixed 50g.

**Only deals that sell:** a deal is shown only if the relist would really sell. It is priced at what you could relist at, not the usual price: just under the cheapest listing you'd leave up, and never above the recent average (the usual price lags when prices fall, as they do on a new server, and deals that counted on it sat unsold). Then, at that price and that AH, it needs a measured sell rate of 1+ a day, a 50%+ chance each listing sells before it runs out (the same chance the tooltip shows), and your own auctions of it in the last 30 days must not have mostly come back unsold. It tells you how many to buy (about a day of sales there, since you're only the cheapest until the next undercut), and the profit is the expected profit after the cut, lost deposits and the chance it doesn't sell. A note at the bottom counts what was left out and why. Crafting and faction vs neutral deals get the same check.

**Will it sell, and where:** every full scan remembers the cheapest 40 listings of each item. On the next scan of the same AH (5 min to 6 h later), listings that are gone count as sold, after taking off the share that would have expired. This gives a sells-per-day estimate for each AH. Cancelled undercuts also look like sales, so treat it as an estimate. Under each deal, the window shows the chance each listing sells at the relist price and how many sell a day at this AH (see Only deals that sell above). Scan both the faction and neutral AH to compare them. Scans more than 6 h apart can't be compared (most listings would have expired anyway), which is why a sell rate often stayed unknown. Now AskAH rescans every 15 min while you stay at the AH (unless you searched in the last 2 min, or `/askah autoscan off`), and your own searches count as a look at that item too. The window says how many items have a measured rate. Where you've sold the item yourself, it also shows your own record from the last 30 days (sold vs didn't sell).

**Staying current:** deals come from the last full scan, but every time you search the AH (or click a deal, or buy one) AskAH checks the listings you see. Deals that are gone drop off, changed ones get updated and marked "Checked live", and new cheap listings it spots are added. The header shows how old the scan is and when the next one comes, and a scan older than 3 h gets a warning.

Each section lists deals in columns (quantity, buy price, sell price, profit) with the item's icon and quality color, and prices shown with gold, silver and copper icons. Hover a line to see the item's tooltip plus AskAH's numbers for it. Click a line to search the AH for it. Click a section heading to fold or unfold it (remembered). While you scroll, the heading and column labels of the section you're in stay pinned to the top. Drag the window to move it, or drag its bottom-right corner to resize it (size is remembered). Your own listings are left out. Use `/askah deals` to open or close the window, and `/askah deals off` or `on` to stop or restore the pop-up.

## My sales

`/askah sales` opens a window with your auction house sales, newest first: item, how many, what it sold for, what you got after the cut (deposit back included), when, which AH (faction or neutral) and the buyer. The top shows today's and the last 7 days' totals. It reads the game's own data, per character:
- the auction house sale mail (Sale Pending / Auction successful): price, buyer, cut and deposit, read when you open a mailbox. AH mail stays 30 days, so past sales still in your inbox show up the first time you open it. AskAH keeps them after you take the gold.
- your Auctions tab at the AH, where sold auctions show "Sold" until the gold is mailed

The game keeps no other sales history (there's no API for it, and no other sales-logging addon was installed), so sales older than the mail in your inbox can't be recovered. A sale seen only on the Auctions tab shows "cut and net come with the AH mail" until you visit a mailbox. Faction vs neutral is worked out from the cut on the mail (5% vs 15%).

**Kept current:** a sale or expiry shows the moment the game announces it ("A buyer has been found...", anywhere in the world), matched to the exact auction. While you're at the AH your auctions are re-read every minute. An auction whose time ran out with no sale shows as "probably expired" right away instead of waiting for the mail, and the sales window updates itself every 30 seconds while open. The hourly Blizzard feed's "probably sold / expired" comes in on /reload or login (addons can't read new files while you play).

**What didn't sell:** auctions that expire (or that you cancel) come back by mail as "Auction expired" / "Auction cancelled". AskAH records those too, marked "didn't sell" (red) or "cancelled", with which AH, how many, and the lowest price there now from your scans so you can relist. Use the All / Sold / Didn't sell buttons at the top of the window, or `/askah sales unsold` in chat.

**My auctions, from anywhere:** each time you're at the AH, AskAH saves the list of your auctions there (it asks the AH a moment after you open it, and again after you post or cancel), one list per AH (faction and neutral). `/askah auctions`, the "Up now" button in the sales window, or "My auctions" in the minimap menu shows them anywhere: buyout, current bid, time left counting down, and a yellow "undercut" note when your last scan saw it cheaper. When the sale or "Auction expired" mail comes in, the line is marked sold or didn't sell. Auctions on all your characters show (tagged with the character's name). Something you post shows at once as "just posted" until the AH's own list comes back. The hourly Blizzard feed follows each auction and marks it "probably sold" or "probably expired" between AH visits; listings without an auction ID are matched by item, stack size and buyout.

## How "sell chance" is worked out

For each auction house, the chance that one listing sells before it expires, at the price AskAH suggests (just under the cheapest). It blends:
- **What the Blizzard feed saw on your own auction houses:** every listing is followed from when it appears until it's gone. Gone before its time ran out counts as sold, gone right when its time ran out counts as expired. Per item, AskAH counts how often listings sold by **place in the queue** (the cheapest, or with hours or days of sales listed cheaper) and by **price against the usual price** (from under 80% to over 2.5x).
- **Items like it:** where an item has few listings, it borrows from items of the same kind and quality with similar demand (green armor that barely sells, cloth that sells 25+ a day, ...), then from everything at that AH. This is the gold-guide rule of thumb (trade goods and consumables move, green gear is slow, overpriced listings sit) measured on your houses instead of guessed.
- **Demand vs competition:** units sold per day against units listed.
- **Your own record:** your sales and "Auction expired" mail for the item, and whether it expired before at this price.
- **TradeSkillMaster's region sale rate**, if TSM is installed.
It then checks itself against what really happened (`/askah accuracy`). Hold Shift on an item to see the reasons, the chance at the usual price behind cheaper listings, and the busiest buying hours at that AH. The feed needs about 2 days after an update to learn how long listings last and to see enough of them expire; until then the chance leans on demand and your own record.

## Hourly Blizzard AH data (no need to stand at the AH)

`Feed\AskAHFeed.ps1` downloads WoW: Forever auction data from Blizzard's web API (your own free API client from develop.battle.net) and writes `FeedData.lua`. Windows Task Scheduler runs it every 20 minutes (`Feed\Install-Schedule.cmd`). On login or `/reload`, AskAH merges it into prices, sell rates and the deals window, which then says "Blizzard data from X ago". Sell rates come from auctions that vanish between hourly snapshots while they still had hours left. Forever's houses are shared per ruleset and the API doesn't say which group is which ruleset, so AskAH matches the houses against your own scans and remembers your group (`/askah feed` shows status, `/askah feed group 1-5` sets it). Setup steps are in `Feed\README.txt`. The API isn't documented by Blizzard yet, so it may change.

### Blizzard game data
After each feed run, `Feed\AskStatic.ps1` keeps `BlizzData.lua` up to date with Blizzard's Forever game data: every item (name, quality, vendor prices), gear stats, item sets and all profession recipes with reagents. It only downloads everything again when Blizzard publishes a new game build. AskAH uses it for:
- upgrade checks on items your game hasn't loaded yet
- `/askah upgrades`: gear for sale on your auction houses (hourly feed) that's an upgrade for your spec
- `/askah craft <profession>`: most profitable recipes, AH price minus reagent cost
- tooltips: item set (and how many pieces you wear), which recipes use the item, what it costs to craft
- `/askah blizz`: status
It also writes AskQuest's `BlizzQuests.lua` (real quest gold and reward items).
