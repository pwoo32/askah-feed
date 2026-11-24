AskAH Feed: auction house data without standing at the AH
==========================================================

This folder has a small script that downloads WoW: Forever auction house data
from Blizzard's web API every hour and saves it to ..\FeedData.lua. When you log
in (or type /reload), AskAH loads it: prices, sell rates and the deals window are
up to date even if you haven't been to the AH.

One-time setup (about 5 minutes)
--------------------------------
1. Make a free API client at https://develop.battle.net/access/clients
   (log in with your Battle.net account, "Create Client", any name, no
   redirect URL needed, tick "I do not have a service URL").
2. Double-click Run-Feed.cmd. The first time it makes config.json and stops.
3. Open config.json in Notepad. Paste the Client ID and Client Secret, set
   "region" to "us" or "eu" (or "kr"/"tw"), save.
4. Double-click Run-Feed.cmd again. The first run downloads every Forever
   auction house (it doesn't know yet which ones are yours), so it takes a
   few minutes.
5. Restart WoW once (new addon files only load on a full restart). Open your
   auction house once so AskAH has your own prices to compare: it then works
   out which houses are yours and says so in chat. Type /reload or log out
   so it saves that.
6. Double-click Run-Feed.cmd once more (now it only downloads your 3 houses),
   then Install-Schedule.cmd so it keeps running every 20 minutes, hidden (no window pops up).

After that: /reload in game any time to load the latest data.
/askah feed in game shows the status. If AskAH can't work out your houses,
set them: /askah feed group 1 (to 5). Group 1 is the PvP ruleset; the others
aren't mapped publicly yet. You can also put "group": 2 in config.json.

Notes
-----
- Your client id and secret stay in config.json on this PC. The script only
  sends them to Blizzard's login server (oauth.battle.net).
- Sell rates: an auction that vanishes between hourly snapshots while it
  still had hours left counts as bought (cancelled ones look the same, except
  a stack reposted at another price), one that vanishes in its last half hour
  expired, and a stack that shrank was partly bought. (Before 0.12.0 a script
  bug read every auction's time left as unknown, so whole-auction sales were
  missed.) If Blizzard ever drops time left, the script falls back on timing
  each listing from when it first shows up. Rates start after two snapshots,
  an hour apart.
- Blizzard hasn't documented the Forever API yet, so it could change. feed.log
  says what happened on each run.
- Remove-Schedule.cmd stops the background runs.

Blizzard game data (AskStatic.ps1)
----------------------------------
At the end of each feed run, AskStatic.ps1 checks Blizzard's game data build
(one small request). When the build is new, it downloads every Forever item
(names, quality, vendor prices), gear stats, item sets, all profession recipes
with reagents, and the gold/XP/reward items of every AskQuest quest, and writes
..\BlizzData.lua (AskAH) and ..\..\AskQuest\BlizzQuests.lua (AskQuest). The
first run takes a few minutes; after that it only looks up items that newly
show up on the AH. Items Forever's data is missing come from Blizzard's
Classic Era data. Cache: the static folder. Rebuild: AskStatic.ps1 -Force.
In game: /askah blizz (status), /askah upgrades, /askah craft <profession>.
