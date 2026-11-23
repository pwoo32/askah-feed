#!/usr/bin/env bash
# One feed pass: get your auctions, put back state, run the feed and game
# data scripts, publish to the "data" branch if anything real changed.
# Run from the job's workspace (main/ and data/ checked out side by side).
set -u
F=main/AskAH/Feed
REBUILD="${1:-false}"

git -C main fetch -q --depth=1 origin pc 2>/dev/null && git -C main show FETCH_HEAD:mine.lua > mine.lua 2>/dev/null || rm -f mine.lua
if [ -s mine.lua ]; then export ASKAH_SV="$PWD/mine.lua"; else unset ASKAH_SV; fi

mkdir -p $F/state $F/static
cp -r data/state/. $F/state/ 2>/dev/null || true
cp -r data/static/. $F/static/ 2>/dev/null || true
cp data/feed.log $F/ 2>/dev/null || true
for f in FeedData.lua BlizzData.lua; do cp data/$f main/AskAH/ 2>/dev/null || true; done
cp data/BlizzQuests.lua main/AskQuest/ 2>/dev/null || true

pwsh -NoProfile -Command '
  $c = [ordered]@{ clientId = $env:CLIENT_ID; clientSecret = $env:CLIENT_SECRET; region = $env:REGION }
  if ($env:GROUP) { $c["group"] = [int]$env:GROUP }
  $c | ConvertTo-Json | Set-Content main/AskAH/Feed/config.json'

ok=0
pwsh -NoProfile -File $F/AskAHFeed.ps1 || ok=1
if [ "$REBUILD" = "true" ]; then pwsh -NoProfile -File $F/AskStatic.ps1 -Force || true; else pwsh -NoProfile -File $F/AskStatic.ps1 || true; fi
rm -f $F/config.json

tail -n 400 $F/feed.log > data/feed.log 2>/dev/null || true
rm -rf data/state data/static && mkdir -p data/state data/static
cp -r $F/state/. data/state/ 2>/dev/null || true
cp -r $F/static/. data/static/ 2>/dev/null || true
for f in FeedData.lua BlizzData.lua; do cp main/AskAH/$f data/ 2>/dev/null || true; done
cp main/AskQuest/BlizzQuests.lua data/ 2>/dev/null || true

cd data
git add -A
# FeedData.lua gets a new timestamp every pass; publish only when something
# real changed (a new snapshot, your auctions, game data)
if git diff --cached --quiet -- . ':!feed.log' ':!FeedData.lua' && \
   [ "$(git diff --cached -U0 -- FeedData.lua | grep -c '^[-+][^-+]')" -le 2 ]; then
  echo "Nothing new from Blizzard; not publishing."
else
  b="run$(date +%s)"
  git checkout -q --orphan "$b"
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -q -m "Feed run $(date -u +%Y-%m-%dT%H:%MZ)"
  pushed=0
  for i in 1 2 3; do git push -q -f origin "$b:data" && { pushed=1; break; }; sleep $((i*5)); done
  if [ $pushed = 1 ]; then echo "Published."; else echo "::error::Couldn't publish to the data branch"; ok=1; fi
fi
exit $ok
