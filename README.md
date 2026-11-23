# askah-feed

Runs the AskAH auction house feed on GitHub every 20 minutes, so prices, sell
rates and "did my auction sell?" keep updating while your PC is off.

## How it fits together

- **`.github/workflows/feed.yml`** runs `AskAH/Feed/AskAHFeed.ps1` (auction
  snapshots, sell rates, your auctions) and then `AskStatic.ps1` (Blizzard game
  data) on a schedule. Your Blizzard API keys come from the repo secrets
  `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`.
- **`data` branch**: what the feed writes (`FeedData.lua`, `BlizzData.lua`,
  `BlizzQuests.lua`), its tracking state (`state/`, `static/`) and `feed.log`.
  It is replaced every run, so it never builds up history. A run that finds
  nothing new from Blizzard doesn't publish.
- **`pc` branch**: `mine.lua`, which your PC uploads: your house group, realm and
  the auction IDs of your own listings, taken from AskAH's SavedVariables.
- **`pc/`**: the scripts for your PC. They go in `Interface\AddOns\AskAH\Feed`.
  `Sync.ps1` downloads the newest files and uploads your auctions, hidden, every
  20 minutes and at logon (`Install-Sync.cmd`).

WoW can't reach the internet, so in game you still `/reload` (or log in) to load
what the sync downloaded.

## Settings (Settings > Secrets and variables > Actions)

| Name | Kind | What |
|---|---|---|
| `BLIZZARD_CLIENT_ID` | secret | from https://develop.battle.net/access/clients |
| `BLIZZARD_CLIENT_SECRET` | secret | same |
| `REGION` | variable (optional) | `us` (default), `eu`, `kr`, `tw` |
| `FEED_GROUP` | variable (optional) | your house group, if AskAH can't work it out |
| `TZ` | variable (optional) | time zone for sales by hour, default `America/New_York` |

## Handy

- Actions tab > AH feed > Run workflow: run it now (tick the box to re-download
  all game data).
- `feed.log` on the `data` branch says what each run did.
- GitHub turns off schedules in public repos after 60 days without commits; the
  feed's own commits count, but if it ever stops, re-enable it in the Actions tab.
- Updating the scripts: copy new `AskAHFeed.ps1` / `AskStatic.ps1` into
  `AskAH/Feed/` here, and `QuestData.lua` into `AskQuest/` when AskQuest's quest
  list changes.
