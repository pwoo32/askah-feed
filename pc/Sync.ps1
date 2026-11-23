# Sync.ps1
# The AH feed now runs on GitHub (every 20 minutes, PC on or off). This keeps
# your addons up to date from it, with no window:
#  - downloads the newest FeedData.lua, BlizzData.lua and BlizzQuests.lua
#  - uploads what the feed needs from AskAH's SavedVariables (your house group,
#    realm and the auction IDs of your own listings, nothing else), so GitHub
#    can tell when your auctions sell
# Install-Sync.cmd runs it every 20 minutes and when you log in to Windows.
#
# Settings: sync.json next to this file.
#   repo   "owner/name" of the GitHub repo
#   token  a fine-grained GitHub token for that one repo (Contents: read and
#          write). Needed to upload your auctions, and to download from a
#          private repo. Leave "" for a public repo without auction tracking.

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonDir = Split-Path -Parent $Here
$AddOnsDir = Split-Path -Parent $AddonDir
$GameDir = Split-Path -Parent (Split-Path -Parent $AddOnsDir)
$LogFile = Join-Path $Here 'sync.log'
$StateFile = Join-Path $Here 'sync-state.json'
$ConfigFile = Join-Path $Here 'sync.json'

function Log($msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 256KB) {
  Set-Content -Path $LogFile -Value (Get-Content $LogFile -Tail 300) -Encoding UTF8
}

# one at a time
try { $script:RunLock = [IO.File]::Open((Join-Path $Here 'sync.lock'), 'OpenOrCreate', 'ReadWrite', 'None') } catch { exit 0 }

if (-not (Test-Path $ConfigFile)) { Log "no sync.json yet (run Install-Sync.cmd)"; exit 1 }
$cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Repo = [string]$cfg.repo
$Token = [string]$cfg.token
if ($Token -like 'PASTE*') { $Token = '' }
if (-not $Repo -or $Repo -notmatch '^[\w.-]+/[\w.-]+$') { Log "sync.json: repo should look like owner/name"; exit 1 }

$state = @{}
if (Test-Path $StateFile) {
  try { (Get-Content $StateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = [string]$_.Value } } catch {}
}
function Save-SyncState { ($state | ConvertTo-Json) | Set-Content -Path $StateFile -Encoding UTF8 }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Api = "https://api.github.com/repos/$Repo"
function Headers([string]$accept = 'application/vnd.github+json') {
  $h = @{ 'User-Agent' = 'AskAH-Sync'; Accept = $accept; 'X-GitHub-Api-Version' = '2022-11-28' }
  if ($Token) { $h['Authorization'] = "Bearer $Token" }
  return $h
}
function Api-Get([string]$path) {
  return Invoke-RestMethod -UseBasicParsing -Uri "$Api$path" -Headers (Headers) -TimeoutSec 60
}

# ---------------------------------------------------------------- 1. download
# The feed keeps its output on the "data" branch (replaced every run).
$Files = [ordered]@{
  'FeedData.lua'    = (Join-Path $AddonDir 'FeedData.lua')
  'BlizzData.lua'   = (Join-Path $AddonDir 'BlizzData.lua')
  'BlizzQuests.lua' = (Join-Path (Join-Path $AddOnsDir 'AskQuest') 'BlizzQuests.lua')
}
try {
  $head = Api-Get '/commits/data'
  $sha = [string]$head.sha
  if ($sha -and $sha -ne $state['dataSha']) {
    $tree = Api-Get "/git/trees/$sha"
    $n = 0
    foreach ($e in $tree.tree) {
      $dest = $Files[[string]$e.path]
      if (-not $dest) { continue }
      if (-not (Test-Path (Split-Path -Parent $dest))) { continue }   # addon not installed
      if ($state["blob:$($e.path)"] -eq $e.sha -and (Test-Path $dest)) { continue }
      $tmp = "$dest.download"
      Invoke-WebRequest -UseBasicParsing -Uri "$Api/git/blobs/$($e.sha)" -Headers (Headers 'application/vnd.github.raw') -OutFile $tmp -TimeoutSec 180
      Move-Item -Force $tmp $dest
      $state["blob:$($e.path)"] = [string]$e.sha
      $n++
    }
    $state['dataSha'] = $sha
    Save-SyncState
    $when = ''
    try { $when = ([DateTimeOffset]$head.commit.committer.date).ToLocalTime().ToString('HH:mm') } catch {}
    Log ("downloaded {0} file(s) from the feed run of {1}. /reload in game to load them." -f $n, $when)
  }
} catch {
  Log "download: $($_.Exception.Message)"
}

# ---------------------------------------------------------------- 2. upload
# Only what AskAHFeed.ps1 reads from SavedVariables: feedGroup, realm names
# and the "auctions" tables (your own listings). Written when you log out or /reload.
if (-not $Token) { exit 0 }
try {
  $sv = Get-ChildItem -Path (Join-Path (Join-Path $GameDir 'WTF') 'Account') -Filter 'AskAH.lua' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*SavedVariables' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $sv) { exit 0 }
  $stamp = [string]$sv.LastWriteTimeUtc.Ticks
  if ($state['svStamp'] -eq $stamp) { exit 0 }

  $txt = [IO.File]::ReadAllText($sv.FullName)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('-- mine.lua: written by Feed\Sync.ps1 from AskAH''s SavedVariables (your house group, realm and auctions only)')
  $m = [regex]::Match($txt, '\["feedGroup"\]\s*=\s*\d+')
  if ($m.Success) { [void]$sb.AppendLine($m.Value + ',') }
  $realms = @{}
  foreach ($r in [regex]::Matches($txt, '\["([^"]+) - (?:Alliance|Horde)"\]')) {
    if (-not $realms.ContainsKey($r.Value)) { $realms[$r.Value] = 1; [void]$sb.AppendLine($r.Value + ' = 1,') }
    if ($realms.Count -ge 10) { break }
  }
  $ai = $txt.IndexOf('["auctions"]')
  while ($ai -ge 0) {
    $open = $txt.IndexOf('{', $ai); if ($open -lt 0) { break }
    $depth = 0; $j = $open
    for (; $j -lt $txt.Length -and $j -lt $open + 500000; $j++) {
      $ch = $txt[$j]
      if ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { break } }
    }
    [void]$sb.AppendLine('["auctions"] = ' + $txt.Substring($open, $j - $open + 1) + ',')
    $ai = $txt.IndexOf('["auctions"]', $j)
  }
  $body = $sb.ToString()
  $hash = [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($body))).Replace('-', '')
  if ($state['svHash'] -ne $hash) {
    $old = $null
    try { $old = [string](Api-Get '/contents/mine.lua?ref=pc').sha } catch {}
    $req = @{ message = 'Update my auctions'; branch = 'pc'; content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body)) }
    if ($old) { $req['sha'] = $old }
    Invoke-RestMethod -UseBasicParsing -Method Put -Uri "$Api/contents/mine.lua" -Headers (Headers) -ContentType 'application/json' -Body ($req | ConvertTo-Json) -TimeoutSec 60 | Out-Null
    $state['svHash'] = $hash
    $n = ([regex]::Matches($body, '\["aid"\]')).Count
    Log "uploaded your auctions ($n with an auction ID) for the feed"
  }
  $state['svStamp'] = $stamp
  Save-SyncState
} catch {
  $msg = $_.Exception.Message
  if ($msg -match '401|403|404') { $msg += ' (check the token in sync.json: it needs Contents read and write on this repo)' }
  Log "upload: $msg"
}
