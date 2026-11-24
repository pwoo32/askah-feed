# AskQuest (WoW: Forever)

Ask about quests in plain words and get a ranked list: best quest, most XP, most gold, most popular, here or in any zone.

## Install
Copy the `AskQuest` folder to `World of Warcraft\_forever_\Interface\AddOns\` and restart the game (or /reload).

## Examples
- `/aq best quest here`
- `/aq which quest gives the most gold in Arathi`
- `/aq most xp for me` (your level -3 to +4, all zones)
- `/aq most popular quests in Duskwood`
- `/aq best dungeon quests level 30-35`
- `/aq solo xp quests anywhere`, `/aq top 5 gold quests in stv`
- `/aq mackreel` (look up a quest by name)
- `/aq` opens the quest chart window: a table with Quest, Lvl, Zone, Quest giver (x, y), XP, Gold, Pop and Type columns. XP, gold and popularity have bars so the big rewards stand out. Click a column header to sort (click again to flip), scroll with the mouse wheel, hover a row for rewards and the verdict, click for details, right-click to pin the giver on your map, shift-click to put the name in chat. Quick buttons: Best here, Most XP here, Most gold here, Popular here, Most XP anywhere, Most gold anywhere, Popular anywhere, Best for me. The "anywhere" buttons search every zone for quests around your level (3 below to 4 above) that you can take and have not done.
- `/aq <question>` prints the top results in chat and opens the chart with all of them
- `/aq info off|on` turns off/on the reward panel at quest givers and in the quest log (the chart always shows it)
- `/aq minimap off|on` hides/shows the minimap button

## What it understands
- **Sort:** gold/money, xp/exp/experience, popular/common. Anything else ranks by **best** (55% XP, 25% gold, 20% popularity).
- **Where:** "here / this area / this zone" = your current zone; a zone or dungeon name (also short names like stv, wpl, epl, ungoro, 1k, brd, sm, zf, gnomer); "anywhere" = all zones.
- **Level:** "level 35", "30-35", "for me". With "here" or no zone it uses your level -3 to +4; with a named zone it shows all levels there.
- **Type:** dungeon, solo, elite. "new in forever" = only Forever-new quests.
- Quests you already finished are hidden (add "completed" to include them). "Done" means the game's completed list says so (read in full at login), you turned it in while AskQuest was running, or you've done or picked up a later step of its chain. With Questie installed, quests you can no longer take are hidden too: the other choice of a "pick one" quest, breadcrumbs to a quest you've already done or picked up, and quests that stop being offered once another is turned in. The chart refreshes the moment you turn a quest in (and again a second later), and when you pick up or abandon one. The header says how many were hidden, and a name search still shows done quests with a [Done] tag. Only quests your faction and class can take are shown.

## Chains that lead into a dungeon (new in 0.7.2)
A quest whose chain eventually leads to a dungeon quest is marked **important**: purple "IMPORTANT - leads to a dungeon quest" verdict and the dungeon quest's name in the reward panel, a purple "!" before its name and "Lead-in" as its type in the chart, an "Important: leads to The Deadmines" tag in chat answers, and it ranks higher for "best" questions. The chain view says "Important: it leads to a dungeon quest". "Dungeon quests" questions include these lead-in quests too. It stops being important once you've done the dungeon quest, or when the dungeon quest is more than 5 levels below you. Chain links come from QuestieDB's Forever data; with Questie installed, breadcrumb quests that point into such a chain count as well.

## The numbers
- **XP:** real Forever values (QuestieDB Forever data, from player traces), at the quest's level.
- **Gold and reward items:** Blizzard's own Forever quest data (`BlizzQuests.lua`, written by AskAH's feed: `AskAH\Feed\AskStatic.ps1`), so Forever-new quests have real gold too. Without it, gold comes from cMaNGOS Classic 1.12 and Forever-new quests show "? gold" until a quest giver shows it to you. Gold you see in game always wins (saved in `AskQuestDB`).
- **Reward upgrades:** with AskAH's Blizzard data, rewards the game hasn't loaded yet still get an upgrade check.
- **Popularity:** an estimate, 0-100. No public play counts exist for Forever, so it is scored from how busy the quest hub is, whether the quest is part of a story chain, whether it is solo, and whether it starts from a dropped item.

Red level in brackets = you can't take it yet.

## Minimap button
Left-click opens the chart, right-click shows the best quests here, drag it around the minimap edge (the spot is saved).

## Go to coordinates
**On the world map:** open the map (M). A "Go to:" box sits in its bottom-left corner. Click it, type `45 62` (or `Duskwood 45 62`) and press Enter: the map jumps there and pings the spot. Next to the box you see the coordinates under your mouse.

**Anywhere else:** type `/aq go` (or shift-click / middle-click the minimap button) to open a small box. Type coordinates like `45 62`, `45.2, 62.8` or `Duskwood 45 62` (short names like stv, epl work) and press Enter: the world map opens on that spot with a pulsing yellow ping and a star marker, the game's map pin is set (it shows on the minimap too), and TomTom gets a waypoint if you have it. An arrow in the box points the way with the distance in yards, and says "You're there!" when you arrive. With no zone typed it uses the zone open on the world map, otherwise the zone you're in. Shortcuts: `/aq 45 62`, `/aq go stv 30 40`, `/aq go clear`. `/way 45 62` works too unless another addon (TomTom) already owns `/way`. The box remembers where you dragged it and stays open after /reload if you left it open.

## Coordinates in the quest tracker (new in 0.7.1)
**Rewards on Questie's map icons.** Hover a Questie quest icon on the world map or minimap and hold **Shift**: under Questie's own details, an "AskQuest rewards" section lists each quest there with its XP, gold, every reward item (choose-one and always-given) with AskQuest's verdict and sale value, and the worth-it rating. Up to 8 quests per icon cluster. Turn it off in Esc > Options > AddOns > AskQuest.

With Questie's quest tracker on (it is by default), every objective you still need starts with the coordinates of the **nearest** spot for it, in blue: `[49, 36] Kobold Vermin slain: 3/10`. For items it's the nearest mob that drops it or object that holds it. It's worked out from Questie's spawn data and where you stand, and it updates every few seconds as you move. Dungeon objectives point to the dungeon entrance.

**Click the [49, 36] tag** to open the world map there with the pulsing ping and star marker; it also sets the game's map pin (minimap too), a TomTom waypoint if you have TomTom, and the "Go to" arrow box. Hover it to see the mob or object name, zone, exact coordinates and distance. Clicking the rest of the line still does Questie's usual thing (left-click opens the quest log, right-click the menu). Turn it off with `/aq tracker off` or in Esc > Options > AddOns > AskQuest.

## Rewards and "worth it?"
Hover a quest in the chart or the quest log, or talk to a quest giver, and a panel shows:
- the quest giver and turn-in NPC: name, zone, coordinates, and how far and which way they are from you (or "not in your zone")
- XP for your level (reduced if the quest is low for you) and as a % of your level
- gold, and every item reward: upgrade or not for your spec (Prot by default; uses AskAH's spec and auction prices when AskAH is installed), vendor or auction value, and which one to pick
- effort: elite, dungeon, turn-in in another zone, not in your zone
- a verdict (GREAT / Worth it / OK if nearby / Skip / Not yet) with the reasons
- the quest chain it belongs to (step X of Y) and where the chain starts: first quest, its giver, zone, coordinates and distance

Item rewards come from Blizzard's Forever quest data when the feed has run, otherwise cMaNGOS; rewards you see in game always win.

## Details panel and map pins
Click a quest in the chart for the full details: every quest step (pick up, what to kill or collect and how many, where the mobs are and what drops the items, your live progress if you have the quest, turn in), rewards, verdict, the whole quest chain (steps, total XP and gold, popularity, do it or skip and why). The **Show quest giver** button pins the giver on your map and minimap (and TomTom if installed) and opens the map there; **Show turn-in** does the same for the turn-in NPC, and **Show chain start** pins the giver of the chain's first quest. Right-click a quest in the chart to pin the giver straight away.

"Best for me" ranks quests from most to least valuable for you right now (the # column is the rank, the Value column is the score with Great / Worth it / OK / Skip) and has a "Why it's good for you" column (also shown for every other question).

## Settings
Esc > Options > AddOns > AskQuest (or `/aq options`) has the on/off switches for the reward panel and the minimap button. `/aq help` lists the commands by topic.

## Boats, zeppelins and the tram (new in 0.7.0)

- **World map:** every dock, zeppelin tower and tram has a coloured marker (B blue boat, Z orange zeppelin, T grey tram) with a label saying where it goes. Hover for the full route. Continent maps show the markers without labels.
- **In the world:** walk onto a dock and a banner pops up: "Menethil Harbor: Boat to Southshore, then Auberdine / Boat to Theramore". Drag it anywhere; X closes it.
- Includes the WoW Forever routes: Stormwind Harbor to Auberdine, the Menethil > Southshore > Auberdine loop, and Steamwheedle Port (Tanaris) to Powderfuse Port (Riverglades).
- A few spots are best guesses (Stormwind Harbor, Southshore dock, Rut'theran, Stormwind tram). Stand on the real dock and type `/aq dock here` to move the marker; it is saved.
- `/aq docks` lists this zone's docks. `/aq docks on|off`, `/aq docks banner on|off`, `/aq docks horde on|off`, `/aq dock add <text>`, `/aq dock reset`.
