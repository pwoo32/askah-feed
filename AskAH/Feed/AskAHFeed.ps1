# AskAHFeed.ps1
# Downloads WoW: Forever auction house data from Blizzard's web API and writes
# it to ..\FeedData.lua for the AskAH addon. Run it by hand (Run-Feed.cmd) or
# every 20 minutes with Install-Schedule.cmd. Blizzard publishes a new
# snapshot about once an hour; runs in between cost one tiny request.
#
# Needs config.json next to this file (your own free API client from
# https://develop.battle.net/access/clients). Your client id and secret only
# go to Blizzard's login server (oauth.battle.net), nowhere else.
#
# Sell rates: an auction that disappears between two hourly snapshots before
# its listing time ran out was bought (or cancelled); one that disappears
# right when its time ran out expired; a stack that shrank was partly bought.
# Each listing is also timed from when it first appeared, in case time left is
# missing. That gives units sold per day and, per item, the share of listings
# that sell by price and by place in the queue.

param([switch]$All)  # -All: fetch every house, not just your group

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonDir = Split-Path -Parent $Here
$OutFile = Join-Path $AddonDir 'FeedData.lua'
$StateDir = Join-Path $Here 'state'
$LogFile = Join-Path $Here 'feed.log'
$ConfigFile = Join-Path $Here 'config.json'

# The scheduled task used to start powershell.exe directly, which flashes a
# window every run. Switch it (once) to Run-Hidden.vbs, which opens no window.
if (-not $env:ASKAH_CLOUD) { try {
  $vbs = Join-Path $Here 'Run-Hidden.vbs'
  $task = Get-ScheduledTask -TaskName 'AskAH Feed' -ErrorAction SilentlyContinue
  if ($task -and (Test-Path $vbs) -and ($task.Actions[0].Execute -notmatch 'wscript')) {
    $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B "' + $vbs + '"')
    Set-ScheduledTask -TaskName 'AskAH Feed' -Action $act | Out-Null
  }
} catch { } }

function Log($msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

# Only one run at a time (the 20-minute task and a manual run can overlap).
# The lock is an open file handle, so it goes away by itself if a run dies.
try {
  $script:RunLock = [IO.File]::Open((Join-Path $Here 'feed.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
  Log "another feed run is still going; skipping this one"
  exit 0
}

# Keep the log short
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 512KB) {
  $tail = Get-Content $LogFile -Tail 500
  Set-Content -Path $LogFile -Value $tail -Encoding UTF8
}

# ---------------------------------------------------------------- JSON helpers
# Windows PowerShell 5.1's ConvertFrom-Json stops at 2 MB; auction files are
# ~10 MB, so use the .NET serializer with the limit raised when it's there.
$script:Json = $null
try {
  Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
  $script:Json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $script:Json.MaxJsonLength = [int]::MaxValue
  $script:Json.RecursionLimit = 100
} catch { $script:Json = $null }

function Parse-Json([string]$text) {
  if ($script:Json) { return $script:Json.DeserializeObject($text) }
  return ($text | ConvertFrom-Json -AsHashtable)
}
function To-Json($obj) {
  if ($script:Json) { return $script:Json.Serialize($obj) }
  return ($obj | ConvertTo-Json -Depth 10 -Compress)
}
# Numbers always with a dot, whatever the Windows language (the addon reads them).
$Inv = [Globalization.CultureInfo]::InvariantCulture
function Fmt([string]$f) { return [string]::Format($Inv, $f, [object[]]$args) }

function Get-Field($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Collections.IDictionary]) {
    # Dictionary/Hashtable have ContainsKey; OrderedDictionary only Contains
    if ($obj.PSObject.Methods['ContainsKey']) { if ($obj.ContainsKey($name)) { return $obj[$name] } else { return $null } }
    if (@($obj.Keys) -contains $name) { return $obj[$name] } else { return $null }
  }
  return $obj.$name
}

# ---------------------------------------------------------------- config
if (-not (Test-Path $ConfigFile)) {
  Copy-Item (Join-Path $Here 'config.example.json') $ConfigFile
  Log "Made config.json. Open it in Notepad, paste your Blizzard API client id and secret, set your region, then run this again."
  exit 1
}
$cfg = Parse-Json ([IO.File]::ReadAllText($ConfigFile))
$ClientId = [string](Get-Field $cfg 'clientId')
$Secret = [string](Get-Field $cfg 'clientSecret')
$Region = ([string](Get-Field $cfg 'region')).ToLower().Trim()
if (-not $ClientId -or $ClientId -like 'PASTE*' -or -not $Secret -or $Secret -like 'PASTE*') {
  Log "config.json still has no client id/secret. See README.txt."
  exit 1
}
if ($Region -notin @('us', 'eu', 'kr', 'tw')) { Log "config.json: region must be us, eu, kr or tw (got '$Region')."; exit 1 }
$Group = Get-Field $cfg 'group'
if ($Group) { $Group = [int]$Group }

# AskAH's SavedVariables (WTF\Account\<account>\SavedVariables\AskAH.lua),
# newest first. In the cloud (GitHub) $env:ASKAH_SV points at the small extract
# your PC uploads instead (Feed\Sync.ps1): group, realm and your auctions only.
function Get-SvFiles {
  if ($env:ASKAH_SV) {
    if (Test-Path $env:ASKAH_SV) { return @(Get-Item $env:ASKAH_SV) }
    return @()
  }
  $gameDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $AddonDir))
  return @(Get-ChildItem -Path (Join-Path (Join-Path $gameDir 'WTF') 'Account') -Filter 'AskAH.lua' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -like '*SavedVariables' } | Sort-Object LastWriteTime -Descending)
}

# Your group of houses, as AskAH worked it out in game (saved when you log out
# or /reload): WTF\Account\<account>\SavedVariables\AskAH.lua
if (-not $Group) {
  $svFiles = Get-SvFiles
  foreach ($f in $svFiles) {
    $m = [regex]::Match([IO.File]::ReadAllText($f.FullName), '\["feedGroup"\]\s*=\s*(\d+)')
    if ($m.Success) { $Group = [int]$m.Groups[1].Value; break }
  }
  # Not worked out yet: go by your realm's ruleset, which is in its name
  # (AskAH saves prices under "<realm> - Alliance/Horde"). Checked against the
  # API: US "RP PvP" realms are group 5; PvP realms are group 1.
  if (-not $Group) {
    foreach ($f in $svFiles) {
      foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '\["([^"]+) - (?:Alliance|Horde)"\]')) {
        $realm = $m.Groups[1].Value
        if ($realm -match '(?i)\bRP[ -]?PvP\b') { if ($Region -eq 'us') { $Group = 5 } }
        elseif ($realm -match '(?i)\bPvP\b') { $Group = 1 }
        if ($Group) { Log "your realm '$realm' is on house group $Group"; break }
      }
      if ($Group) { break }
    }
  }
}

# house id -> group, kind. Note: index it as $Houses[[object]$id]; on an
# [ordered] dictionary a plain int index means "position", not "key".
# (community-mapped; the API doesn't say which group is
# which ruleset, so AskAH matches them against your own scans in game)
$Houses = [ordered]@{
  110 = @(1, 'alliance'); 113 = @(1, 'horde'); 116 = @(1, 'blackwater')
  111 = @(2, 'alliance'); 114 = @(2, 'horde'); 117 = @(2, 'blackwater')
  112 = @(3, 'alliance'); 115 = @(3, 'horde'); 118 = @(3, 'blackwater')
  119 = @(4, 'alliance'); 120 = @(4, 'horde'); 121 = @(4, 'blackwater')
  123 = @(5, 'alliance'); 124 = @(5, 'horde'); 125 = @(5, 'blackwater')
}
$want = @()
foreach ($id in $Houses.Keys) { if ($All -or -not $Group -or $Houses[[object]$id][0] -eq $Group) { $want += $id } }
$full = [bool]$Group   # full data (listings, history, sell rates) once we know your group

# Your own auctions: AskAH saves their auction IDs from your Auctions tab (in
# SavedVariables, on logout or /reload). Each run checks whether they're still
# up; one that vanished with hours left probably sold, one that vanished in
# its last half hour probably expired. state\mine.json keeps what we saw.
$Mine = @{}
$MineLoose = @{}   # "item,qty,unit" for listings saved without an auction ID (classic-style AH)
$MineKey = @{}     # "item,qty,unit" -> the auction ID the feed matched it to
try {
  foreach ($f in (Get-SvFiles)) {
    $txt = [IO.File]::ReadAllText($f.FullName)
    $ai = $txt.IndexOf('["auctions"]')
    while ($ai -ge 0) {
      # only the "auctions" tables (your listings), not the sales history:
      # take everything up to the brace that closes this table
      $open = $txt.IndexOf('{', $ai); $depth = 0; $j = $open
      if ($open -lt 0) { break }
      for (; $j -lt $txt.Length -and $j -lt $open + 500000; $j++) {
        $ch = $txt[$j]
        if ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { break } }
      }
      $chunk = $txt.Substring($open, $j - $open + 1)
      foreach ($m in [regex]::Matches($chunk, '\["aid"\]\s*=\s*(\d+)')) { $Mine[$m.Groups[1].Value] = 1 }
      foreach ($e in [regex]::Matches($chunk, '\{[^{}]*\}')) {
        $b = $e.Value
        if ($b -match '\["aid"\]') { continue }
        $mi = [regex]::Match($b, '\["id"\]\s*=\s*(\d+)'); $mq = [regex]::Match($b, '\["q"\]\s*=\s*(\d+)')
        $mb = [regex]::Match($b, '\["buyout"\]\s*=\s*(\d+)')
        if ($mi.Success -and $mq.Success -and $mb.Success -and [int64]$mq.Groups[1].Value -gt 0) {
          $u = [math]::Floor([double]$mb.Groups[1].Value / [double]$mq.Groups[1].Value)
          $MineLoose["$($mi.Groups[1].Value),$($mq.Groups[1].Value),$u"] = 1
        }
      }
      $ai = $txt.IndexOf('["auctions"]', $ai + 12)
    }
  }
} catch {}
$MineFile = Join-Path $StateDir 'mine.json'
$MineState = @{}   # aid -> "status,t,q0,qNow,iid,house" (status: up, sold, expired, ended)
if (Test-Path $MineFile) { try { $d = Parse-Json ([IO.File]::ReadAllText($MineFile)); foreach ($k in $d.Keys) { $MineState[$k] = [string]$d[$k] } } catch {} }
$MineKeyFile = Join-Path $StateDir 'minekey.json'
if (Test-Path $MineKeyFile) { try { $d = Parse-Json ([IO.File]::ReadAllText($MineKeyFile)); foreach ($k in $d.Keys) { $MineKey[$k] = [string]$d[$k] } } catch {} }
# listings without an auction ID: find the one auction with the same item,
# stack size and unit buyout (only if exactly one matches, so it's yours)
function Match-Loose($now, $id) {
  if (-not $MineLoose.Count) { return }
  $hits = @{}
  foreach ($aid in $now.Keys) {
    $c = $now[$aid].Split(',')
    $k = "$($c[0]),$($c[1]),$($c[3])"
    if ($MineLoose.ContainsKey($k)) { if ($hits.ContainsKey($k)) { $hits[$k] = '' } else { $hits[$k] = $aid } }
  }
  foreach ($k in $hits.Keys) { if ($hits[$k]) { $Mine[$hits[$k]] = 1; $MineKey[$k] = $hits[$k] } }
}

function Update-Mine($id, $now, $prevSnap, [int64]$t, $byItem, [int64]$gap) {
  foreach ($aid in @($Mine.Keys) + @($MineState.Keys) | Select-Object -Unique) {
    $old = $MineState[$aid]; $o = if ($old) { $old.Split(',') } else { $null }
    $cur = $now[$aid]
    if ($cur) {
      $c = $cur.Split(',')
      $q0 = if ($o -and $o[0] -eq 'up') { $o[2] } else { $c[1] }
      # where you stand: time left band, your unit price, units listed
      # cheaper than yours, and the lowest unit price there now
      $unit = [int64]$c[3]; $ahead = 0; $low = $unit
      if ($byItem -and $byItem.ContainsKey([int]$c[0])) {
        foreach ($l in $byItem[[int]$c[0]]) {
          if ($l[0] -lt $unit) { $ahead += $l[1] }
          if ($l[0] -lt $low) { $low = $l[0] }
        }
      }
      $MineState[$aid] = "up,$t,$q0,$($c[1]),$($c[0]),$id,$($c[2]),$unit,$ahead,$low"
    } elseif ($o -and $o[0] -eq 'up' -and $o[5] -eq [string]$id) {
      $res = 'u'
      if ($prevSnap -and $prevSnap.ContainsKey($aid)) {
        $pf = ([string]$prevSnap[$aid]).Split(',')
        $res = (Classify $pf $null $t $gap -Quiet).Split(',')[0]
      }
      $status = if ($res -eq 's') { 'sold' } elseif ($res -eq 'e') { 'expired' } else { 'ended' }
      $MineState[$aid] = "$status,$t,$($o[2]),0,$($o[4]),$id"
    }
  }
}

# ---------------------------------------------------------------- web
$ApiHost = "https://$Region.api.blizzard.com"
$Ns = "dynamic-forever-$Region"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Token {
  $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ClientId}:${Secret}"))
  $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://oauth.battle.net/token' `
    -Headers @{ Authorization = "Basic $pair" } -ContentType 'application/x-www-form-urlencoded' `
    -Body 'grant_type=client_credentials' -TimeoutSec 60
  $j = Parse-Json $r.Content
  return [string](Get-Field $j 'access_token')
}

# Returns @{ Status; Content; LastModified }  (Status 304 = nothing new)
function Get-Api([string]$path, [string]$since) {
  $uri = "$ApiHost$path" + $(if ($path.Contains('?')) { '&' } else { '?' }) + "namespace=$Ns&locale=en_US"
  $headers = @{ Authorization = "Bearer $script:Token" }
  if ($since) { $headers['If-Modified-Since'] = $since }
  for ($try = 0; $try -lt 3; $try++) {
    try {
      $r = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers $headers -TimeoutSec 180
      $lm = $r.Headers['Last-Modified']
      if ($lm -is [array]) { $lm = $lm[0] }
      # PowerShell 7 hands back bytes when the reply isn't marked as text
      $body = $r.Content
      if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
      return @{ Status = [int]$r.StatusCode; Content = $body; LastModified = [string]$lm }
    } catch {
      $resp = $_.Exception.Response
      $code = 0
      if ($resp) { $code = [int]$resp.StatusCode }
      if ($code -eq 304) { return @{ Status = 304 } }
      if ($code -eq 404) { return @{ Status = 404 } }
      if ($code -eq 401 -or $code -eq 403) { throw "Blizzard refused the request ($code). Check the client id/secret in config.json." }
      if ($try -lt 2 -and ($code -eq 429 -or $code -ge 500 -or $code -eq 0)) { Start-Sleep -Seconds (5 * ($try + 1)); continue }
      throw
    }
  }
}

function Unix([string]$httpDate) {
  try {
    # HTTP dates are GMT; without these styles .NET treats them as local time
    $styles = [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal'
    $d = [DateTime]::ParseExact($httpDate, 'r', [Globalization.CultureInfo]::InvariantCulture, $styles)
    return [int64]([DateTimeOffset]$d).ToUnixTimeSeconds()
  } catch { return [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
}

$TL = @{ 'SHORT' = 1; 'MEDIUM' = 2; 'LONG' = 3; 'VERY_LONG' = 4 }
# time_left as 1-4 (0 = not given): "SHORT" to "VERY_LONG". (Up to 0.11.0 the
# script stored it in $tl, which in PowerShell is the same variable as $TL,
# so after the first listing every one read as 0 and whole-listing sales were
# never counted.) Also accepts { type = ... } and lower case.
function TL-Of($x) {
  $v = Get-Field $x 'time_left'
  if ($v -is [System.Collections.IDictionary]) { $v = Get-Field $v 'type' }
  if ($null -eq $v -or [string]$v -eq '') {
    if (-not $script:TLNote) { $script:TLNote = 1; Log "note: the auction data has no time_left; sold vs expired is worked out from how long each listing was up" }
    return 0
  }
  $s = ([string]$v).ToUpper().Replace(' ', '_')
  if ($script:TL.ContainsKey($s)) { return $script:TL[$s] }
  if (-not $script:TLNote) { $script:TLNote = 1; Log "note: time_left came as '$s' (not understood); sold vs expired is worked out from how long each listing was up" }
  return 0
}

# Listing lengths. Without time_left, a listing that vanishes right at one of
# the lengths it can be posted for probably expired; anywhere else it was
# bought (or cancelled). Which lengths are real is learned from the data:
# listings that vanish pile up at the real ones.
$Candidates = @(2, 8, 12, 24, 48)
$script:AgeHist = [double[]]::new(61)
$script:Durations = @{}
function Learn-Durations($ages) {
  # D -> 1 (a real listing length), 0 (not one), -1 (can't tell yet)
  $r = @{}; $tot = 0.0; foreach ($a in $ages) { $tot += $a }
  foreach ($D in $Candidates) {
    $old = 0.0; for ($k = [math]::Max(0, $D - 3); $k -lt $ages.Count; $k++) { $old += $ages[$k] }
    if ($tot -lt 1500 -or $old -lt 200) { $r[$D] = -1; continue }
    $c = $ages[$D] + $ages[$D + 1]
    $b = 0.0; foreach ($k in @(($D - 3), ($D - 2), ($D + 3), ($D + 4))) { if ($k -ge 0 -and $k -lt $ages.Count) { $b += $ages[$k] } }
    if ($c -ge $b + 30) { $r[$D] = 1 } else { $r[$D] = 0 }
  }
  return $r
}

# Did a listing seen in the last snapshot sell? $p = its saved fields
# (item, qty, time left, unit price, first seen), $cur = the same auction now.
# Returns "s,<units bought>", "e,0" (expired) or "u,0" (can't tell).
function Classify([string[]]$p, $cur, [int64]$t, [int64]$gap, [switch]$Quiet) {
  $pq = [int]$p[1]; $ptl = [int]$p[2]
  if ($cur) {
    $cq = [int](([string]$cur).Split(',')[1])
    if ($cq -lt $pq) { return "s,$($pq - $cq)" }
    return "u,0"
  }
  if ($ptl -ge 3) { return "s,$pq" }
  if ($ptl -eq 1) { return "e,0" }
  if ($ptl -eq 2) { return "u,0" }
  $fs = [int64]0; if ($p.Count -ge 5) { $fs = [int64]$p[4] }
  if ($fs -le 0) { return "u,0" }
  # posted between the snapshot before it was first seen and first seen;
  # ended between the last snapshot and this one
  $mid = ($t - $fs) / 3600.0
  if (-not $Quiet) {
    $bin = [int][math]::Floor($mid); if ($bin -gt 60) { $bin = 60 }; if ($bin -lt 0) { $bin = 0 }
    $script:AgeHist[$bin] += 1
  }
  $lo = ($t - $gap - $fs) / 3600.0 - 0.1; $hi = $mid + 1.1
  foreach ($D in $Candidates) {
    if ($D -ge $lo -and $D -le $hi) {
      $k = $script:Durations[$D]
      if ($k -eq 1) { return "e,0" }
      if ($k -ne 0) { return "u,0" }
    }
  }
  return "s,$pq"
}

# ---------------------------------------------------------------- per house
function Load-State($id) {
  $f = Join-Path $StateDir "house-$id.json"
  if (Test-Path $f) { return Parse-Json ([IO.File]::ReadAllText($f)) }
  return $null
}
function Save-State($id, $st) {
  if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
  $f = Join-Path $StateDir "house-$id.json"
  [IO.File]::WriteAllText("$f.tmp", (To-Json $st))
  Move-Item -Force "$f.tmp" $f
}

# Sell-through counts per item, slowly forgotten (x0.995 per hourly snapshot:
# a listing counts half after about 6 days):
#  [0..3]   sold / expired listings near the lowest price, and above it
#  [4..15]  sold / expired by place in the queue: how many days of sales were
#           listed cheaper (it was the cheapest, <6h, <1 day, <3, <10, more)
#  [16..29] sold / expired by price against the usual price
#           (up to 0.8x, 0.95x, 1.05x, 1.2x, 1.5x, 2.5x, more)
$NC = 30
$Decay = 0.995
function PosBin([double]$ahead, [double]$spd) {
  if ($ahead -le 0) { return 0 }
  $d = $ahead / [math]::Max($spd, 0.2)
  if ($d -lt 0.25) { return 1 }; if ($d -lt 1) { return 2 }; if ($d -lt 3) { return 3 }; if ($d -lt 10) { return 4 }
  return 5
}
function RatBin([double]$r) {
  if ($r -le 0.8) { return 0 }; if ($r -le 0.95) { return 1 }; if ($r -le 1.05) { return 2 }; if ($r -le 1.2) { return 3 }
  if ($r -le 1.5) { return 4 }; if ($r -le 2.5) { return 5 }
  return 6
}
function Num($x) {
  if ($null -eq $x -or [string]$x -eq '') { return 0.0 }
  $d = 0.0
  if ([double]::TryParse([string]$x, [Globalization.NumberStyles]::Float, $Inv, [ref]$d)) { return $d }
  return 0.0
}
# history: "avg,seen,qa,spd,spdN,c0,c1,c2,c3;queue pairs;price pairs"
function Hist-Parse([string]$s) {
  $base = New-Object double[] 5; $c = New-Object double[] $NC
  if ($s) {
    $parts = $s.Split(';')
    $v = $parts[0].Split(',')
    for ($i = 0; $i -lt 5 -and $i -lt $v.Count; $i++) { $base[$i] = Num $v[$i] }
    # older files counted almost no whole-listing sales: their counts start afresh
    if ($parts.Count -ge 3) {
      for ($i = 0; $i -lt 4 -and $i + 5 -lt $v.Count; $i++) { $c[$i] = Num $v[$i + 5] }
      $k = 4
      foreach ($seg in @($parts[1], $parts[2])) {
        foreach ($pr in $seg.Split(',')) {
          if ($k -ge $NC) { break }
          $ab = $pr.Split('/')
          if ($ab.Count -eq 2) { $c[$k] = Num $ab[0]; $c[$k + 1] = Num $ab[1] }
          $k += 2
        }
      }
    }
  }
  return @{ b = $base; c = $c }
}
function Fmt-Pairs($c, [int]$from, [int]$to) {
  $a = New-Object System.Collections.Generic.List[string]
  for ($k = $from; $k -lt $to; $k += 2) {
    if ($c[$k] -lt 0.005 -and $c[$k + 1] -lt 0.005) { $a.Add('0') } else { $a.Add((Fmt '{0:0.##}/{1:0.##}' $c[$k] $c[$k + 1])) }
  }
  return ($a -join ',')
}
function Fmt-Counts($c) {
  return (Fmt '{0:0.##},{1:0.##},{2:0.##},{3:0.##}' $c[0] $c[1] $c[2] $c[3]) + ';' + (Fmt-Pairs $c 4 16) + ';' + (Fmt-Pairs $c 16 30)
}

function Process-House($id) {
  $st = Load-State $id
  $since = $null
  if ($st -and (Get-Field $st 'full') -eq $full) { $since = Get-Field $st 'lm' }
  $main = Get-Api "/data/wow/ruleset/1/auctions/$id" $since
  if ($main.Status -eq 304) { return $st }
  if ($main.Status -eq 404) { Log "house ${id}: not found"; return $st }
  $t = Unix $main.LastModified
  # same snapshot as last time (server ignored If-Modified-Since): nothing to do
  # (a saved time in the future came from the old time-zone bug: ignore it)
  $stT = 0; if ($st) { $stT = [int64](Get-Field $st 't') }
  if ($stT -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 600) { $stT = 0 }
  if ($st -and (Get-Field $st 'full') -eq $full -and $t -le $stT) { return $st }
  $com = Get-Api "/data/wow/ruleset/1/auctions/$id/commodities" $null

  $list = New-Object System.Collections.ArrayList
  $a = Get-Field (Parse-Json $main.Content) 'auctions'
  if ($a) { [void]$list.AddRange(@($a)) }
  if ($com.Status -eq 200) {
    $c = Get-Field (Parse-Json $com.Content) 'auctions'
    if ($c) { [void]$list.AddRange(@($c)) }
  }
  if ($list.Count -eq 0) { Log "house ${id}: empty"; return $null }

  # the last snapshot: any age to carry first-seen times over, and for sold
  # checks only if it's 20 min to 3 h old
  $oldSnap = $null; $prevSnap = $null; $gap = 0
  if ($full -and $st) { $oldSnap = Get-Field $st 'snap' }
  if ($oldSnap) {
    $gap = $t - [int64](Get-Field $st 't')
    if ($gap -ge 1200 -and $gap -le 3 * 3600) { $prevSnap = $oldSnap }
  }
  # how long listings were up when they vanished (learns the listing lengths)
  $script:AgeHist = [double[]]::new(61)
  $sa = Get-Field $st 'ages'
  if ($sa) { $i = 0; foreach ($x in $sa) { if ($i -lt 61) { $script:AgeHist[$i] = [double]$x * 0.999 }; $i++ } }
  $script:Durations = Learn-Durations $script:AgeHist
  # sales by hour of the day (your PC's time), all items together
  $hours = [double[]]::new(24)
  $sh = Get-Field $st 'hours'
  if ($sh) { $i = 0; foreach ($x in $sh) { if ($i -lt 24) { $hours[$i] = [double]$x * 0.998 }; $i++ } }
  $ageSince = [int64]$t
  if ($st -and (Get-Field $st 'ageSince')) { $ageSince = [int64](Get-Field $st 'ageSince') }

  # group listings by item; remember each auction for next time's sold check
  $byItem = @{}
  $now = @{}
  $tlN = 0
  foreach ($x in $list) {
    $item = Get-Field $x 'item'
    $iid = [int](Get-Field $item 'id')
    if (-not $iid) { continue }
    $q = Get-Field $x 'quantity'; if (-not $q) { $q = 1 }; $q = [int]$q
    $unit = Get-Field $x 'unit_price'
    if (-not $unit) {
      $bo = Get-Field $x 'buyout'
      if (-not $bo) { continue }   # bid-only
      $unit = [math]::Floor([double]$bo / $q)
    }
    $unit = [int64]$unit
    if (-not $byItem.ContainsKey($iid)) { $byItem[$iid] = New-Object System.Collections.ArrayList }
    [void]$byItem[$iid].Add(@($unit, $q))
    $aid = [string](Get-Field $x 'id')
    # (not $tl: PowerShell names ignore case, so $tl would hide $TL inside TL-Of)
    $tlv = TL-Of $x
    if ($tlv -gt 0) { $tlN++ }
    # first seen: carried over; new since a recent snapshot = now; else unknown
    $fs = 0
    if ($oldSnap -and $oldSnap.ContainsKey($aid)) {
      $pp = ([string]$oldSnap[$aid]).Split(','); if ($pp.Count -ge 5) { $fs = $pp[4] }
    } elseif ($prevSnap) { $fs = $t }
    $now[$aid] = "$iid,$q,$tlv,$unit,$fs"
  }
  if ($full -and $MineLoose.Count) { try { Match-Loose $now $id } catch { Log "my auctions (match): $($_.Exception.Message)" } }
  if ($full -and ($Mine.Count -or $MineState.Count)) { try { Update-Mine $id $now $prevSnap $t $byItem $gap } catch { Log "my auctions: $($_.Exception.Message)" } }

  # sold since the last snapshot, and per listing whether it sold or expired
  # (see Classify; cancels still look like sales, except cancel-and-repost of
  # the same stack, which is skipped). Counted by price and by place in the
  # queue, which gives each item's chance that a listing sells.
  $out = @{}
  $prevMin = @{}
  $prevItems = Get-Field $st 'items'
  if ($prevItems) { foreach ($kv in $prevItems.GetEnumerator()) { $f = ([string]$kv.Value).Split(',')[0]; if ($f) { $prevMin[[int]$kv.Key] = [double]$f } } }
  $hist = @{}
  if ($st -and (Get-Field $st 'hist')) { foreach ($kv in (Get-Field $st 'hist').GetEnumerator()) { $hist[[string]$kv.Key] = [string]$kv.Value } }
  $sold = @{}
  $events = 0
  if ($prevSnap) {
    # last snapshot's listings per item (unit price, qty)
    $prevBy = @{}
    foreach ($kv in $prevSnap.GetEnumerator()) {
      $p = ([string]$kv.Value).Split(',')
      $ii = [int]$p[0]
      if (-not $prevBy.ContainsKey($ii)) { $prevBy[$ii] = New-Object System.Collections.ArrayList }
      [void]$prevBy[$ii].Add(@([int64]$p[3], [int]$p[1]))
    }
    # listings new in this snapshot, by item and stack size
    $fresh = @{}
    foreach ($aid in $now.Keys) {
      if (-not $prevSnap.ContainsKey($aid)) {
        $c = $now[$aid].Split(','); $k = "$($c[0]),$($c[1])"
        if (-not $fresh.ContainsKey($k)) { $fresh[$k] = New-Object System.Collections.ArrayList }
        [void]$fresh[$k].Add([int64]$c[3])
      }
    }
    $info = @{}
    $hour = [DateTimeOffset]::FromUnixTimeSeconds($t - [int64]($gap / 2)).ToLocalTime().Hour
    foreach ($kv in $prevSnap.GetEnumerator()) {
      $aid = [string]$kv.Key
      $p = ([string]$kv.Value).Split(',')
      if ($p.Count -lt 4) { continue }
      $iid = [int]$p[0]; $pq = [int]$p[1]; $pu = [int64]$p[3]
      if (-not $sold.ContainsKey($iid)) { $sold[$iid] = 0 }
      $cur = $now[$aid]
      $r = (Classify $p $cur $t $gap).Split(',')
      $res = $r[0]; $n = [int]$r[1]
      if ($res -eq 'u') { continue }
      # gone with time left while the same stack came back at another price,
      # where few are listed: a seller cancelled and reposted, not a sale
      if ($res -eq 's' -and -not $cur -and $prevBy[$iid].Count -le 10) {
        $fk = "$iid,$pq"
        if ($fresh.ContainsKey($fk)) {
          $hit = -1
          for ($j = 0; $j -lt $fresh[$fk].Count; $j++) { if ($fresh[$fk][$j] -ne $pu) { $hit = $j; break } }
          if ($hit -ge 0) { $fresh[$fk].RemoveAt($hit); continue }
        }
      }
      if ($n -gt 0) { $sold[$iid] += $n; $hours[$hour] += 1 }
      $events++
      if (-not $info.ContainsKey($iid)) {
        $hv = @(0, 0, 0, 0)
        if ($hist.ContainsKey([string]$iid)) { $hv = @($hist[[string]$iid].Split(';')[0].Split(',')) + @(0, 0, 0, 0) }
        $info[$iid] = @((Num $hv[0]), (Num $hv[3]))
      }
      $inf = $info[$iid]
      $ahead = 0; foreach ($l in $prevBy[$iid]) { if ($l[0] -lt $pu) { $ahead += $l[1] } }
      $pmn = if ($prevMin.ContainsKey($iid)) { $prevMin[$iid] } else { [double]$pu }
      $avg = $inf[0]; if ($avg -le 0) { $avg = $pmn }
      if (-not $out.ContainsKey($iid)) { $out[$iid] = New-Object double[] $NC }
      $o = $out[$iid]; $e = 0; if ($res -eq 'e') { $e = 1 }
      $nb = 2; if ($pu -le $pmn * 1.05) { $nb = 0 }
      $o[$nb + $e] += 1
      $o[4 + 2 * (PosBin $ahead $inf[1]) + $e] += 1
      $o[16 + 2 * (RatBin ($pu / [math]::Max(1.0, $avg))) + $e] += 1
    }
  }

  # per item: min, market (price at the cheapest 25% of units, as in game),
  # history (running averages like AskAH's own), sell rate, sell-through
  # counts, cheapest listings
  $items = [ordered]@{}
  foreach ($iid in $byItem.Keys) {
    $rows = @($byItem[$iid] | Sort-Object { $_[0] })
    $qty = 0; foreach ($r in $rows) { $qty += $r[1] }
    $want25 = [math]::Max(1, $qty * 0.25); $acc = 0; $m = $rows[-1][0]
    foreach ($r in $rows) { $acc += $r[1]; if ($acc -ge $want25) { $m = $r[0]; break } }
    $min = $rows[0][0]
    if (-not $full) { $items[[string]$iid] = "$min,$m,$qty"; continue }

    $hp = Hist-Parse $hist[[string]$iid]
    $h = $hp.b; $c = $hp.c
    for ($k = 0; $k -lt $NC; $k++) { $c[$k] = $c[$k] * $Decay }
    if ($out.ContainsKey($iid)) { $o = $out[$iid]; for ($k = 0; $k -lt $NC; $k++) { $c[$k] += $o[$k] } }
    $th = Fmt-Counts $c
    $prevAvg = $h[0]; $prevSeen = [int]$h[1]
    $avg = if ($prevSeen -gt 0) { $h[0] * 0.7 + $m * 0.3 } else { $m }
    $qa = if ($prevSeen -gt 0) { $h[2] * 0.7 + $qty * 0.3 } else { $qty }
    $spd = $h[3]; $spdN = [int]$h[4]
    if ($sold.ContainsKey($iid)) {
      $perDay = $sold[$iid] * 86400.0 / $gap
      $spd = if ($spdN -gt 0) { $spd * 0.7 + $perDay * 0.3 } else { $perDay }
      $spdN++
    }
    $hist[[string]$iid] = (Fmt '{0:0},{1},{2:0.##},{3:0.###},{4},' $avg ($prevSeen + 1) $qa $spd $spdN) + $th
    $cheap = ($rows | Select-Object -First 12 | ForEach-Object { "$($_[0]):$($_[1])" }) -join ','
    $pa = if ($prevSeen -gt 0) { $prevAvg } else { 0 }
    $items[[string]$iid] = (Fmt '{0},{1},{2},{3:0},{4},{5:0},{6},{7:0.##},{8:0.###},{9},' $min $m $qty $avg ($prevSeen + 1) $pa $prevSeen $qa $spd $spdN) + $th + '|' + $cheap
  }
  # items that sold out completely still count as sold
  if ($full) {
    foreach ($iid in $sold.Keys) {
      if (-not $byItem.ContainsKey($iid) -and $hist.ContainsKey([string]$iid)) {
        $hp = Hist-Parse $hist[[string]$iid]
        $h = $hp.b; $c = $hp.c
        for ($k = 0; $k -lt $NC; $k++) { $c[$k] = $c[$k] * $Decay }
        if ($out.ContainsKey($iid)) { $o = $out[$iid]; for ($k = 0; $k -lt $NC; $k++) { $c[$k] += $o[$k] } }
        $perDay = $sold[$iid] * 86400.0 / $gap
        $spd = if ($h[4] -gt 0) { $h[3] * 0.7 + $perDay * 0.3 } else { $perDay }
        $hist[[string]$iid] = (Fmt '{0:0},{1},{2:0.##},{3:0.###},{4},' $h[0] ([int]$h[1]) $h[2] $spd ([int]$h[4] + 1)) + (Fmt-Counts $c)
      }
    }
  }

  $new = @{ t = $t; lm = $main.LastModified; full = $full; items = $items; count = $list.Count }
  if ($full) {
    $new['snap'] = $now; $new['hist'] = $hist
    $new['hasTL'] = ($tlN -gt $list.Count / 2)
    # plain arrays: New-Object output is wrapped, which the JSON writer can't save
    $new['ages'] = [double[]]@($script:AgeHist); $new['hours'] = [double[]]@($hours); $new['ageSince'] = [int64]$ageSince
    $dl = @(); foreach ($D in $Candidates) { if ($script:Durations[$D] -eq 1) { $dl += "${D}h" } }
    $new['durations'] = ($dl -join ' ')
  }
  Save-State $id $new
  $what = if ($prevSnap) { "sell rates updated, $events listings resolved" } elseif ($full) { "sell rates start next hour" } else { "prices only, until AskAH knows your houses" }
  if ($prevSnap -and $id -eq $want[0]) {
    $dl = @(); foreach ($D in $Candidates) { $dl += ("{0}h:{1}" -f $D, $script:Durations[$D]) }
    $what += "; listing lengths (1 = real, -1 = not known yet): " + ($dl -join ' ')
  }
  Log ("house {0}: {1} auctions, {2} items ({3})" -f $id, $list.Count, $byItem.Count, $what)
  return $new
}

# ---------------------------------------------------------------- run
try {
  $script:Token = Get-Token
} catch {
  Log "couldn't log in to Blizzard's API: $($_.Exception.Message)"
  exit 1
}

$out = New-Object System.Text.StringBuilder
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
[void]$out.AppendLine('-- FeedData.lua: written by Feed\AskAHFeed.ps1. Do not edit; it is replaced every run.')
[void]$out.AppendLine("AskAHFeed = { v = 1, region = `"$Region`", t = $stamp, houses = {} }")
if ($Group) { [void]$out.AppendLine("AskAHFeed.group = $Group") }
$got = 0
foreach ($id in $want) {
  try {
    $st = Process-House $id
  } catch {
    Log "house ${id}: $($_.Exception.Message)"
    $st = Load-State $id
  }
  if (-not $st) { continue }
  $items = Get-Field $st 'items'
  if (-not $items) { continue }
  $isFull = [bool](Get-Field $st 'full')
  $kind = $Houses[[object]$id][1]
  # one function per house keeps each under Lua's constant limit
  # sales by hour of day and since when listings have been timed (for AskAH's sell chances)
  $extra = ''
  $hrs = Get-Field $st 'hours'
  if ($hrs) { $extra += ', hours = { ' + ((@($hrs) | ForEach-Object { Fmt '{0:0.#}' ([double]$_) }) -join ',') + ' }' }
  $as = Get-Field $st 'ageSince'
  if ($as) { $extra += ", since = $as" }
  $du = Get-Field $st 'durations'
  if ($du) { $extra += ", durations = `"$du`"" }
  if (Get-Field $st 'hasTL') { $extra += ", hasTL = true" }
  [void]$out.AppendLine("AskAHFeed.houses[$id] = (function() return { kind = `"$kind`", t = $(Get-Field $st 't'), full = $(if ($isFull) { 'true' } else { 'false' })$extra, items = {")
  foreach ($kv in $items.GetEnumerator()) { [void]$out.AppendLine("[$($kv.Key)]=`"$($kv.Value)`",") }
  [void]$out.AppendLine('} } end)()')
  $got++
}
if ($got -eq 0) { Log "no auction data written (see messages above)"; exit 1 }
# your auctions: keep 3 days of results
if ($MineState.Count) {
  $cut = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 3 * 86400
  $keep = @{}
  foreach ($k in @($MineState.Keys)) { $p = $MineState[$k].Split(','); if ([int64]$p[1] -ge $cut) { $keep[$k] = $MineState[$k] } }
  if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir | Out-Null }
  [IO.File]::WriteAllText($MineFile, (To-Json $keep))
  [void]$out.AppendLine('AskAHFeed.mine = {')
  foreach ($k in $keep.Keys) { [void]$out.AppendLine("[$k]=`"$($keep[$k])`",") }
  [void]$out.AppendLine('}')
  # keys for listings matched by item / stack / price, kept while followed
  $keepKey = @{}
  foreach ($k in $MineKey.Keys) { if ($keep.ContainsKey($MineKey[$k])) { $keepKey[$k] = $MineKey[$k] } }
  [IO.File]::WriteAllText($MineKeyFile, (To-Json $keepKey))
  [void]$out.AppendLine('AskAHFeed.mineKey = {')
  foreach ($k in $keepKey.Keys) { [void]$out.AppendLine("[`"$k`"]=$($keepKey[$k]),") }
  [void]$out.AppendLine('}')
  $sold = @($keep.Values | Where-Object { $_.StartsWith('sold') }).Count
  Log ("your auctions: {0} followed, {1} probably sold in the last 3 days" -f $keep.Count, $sold)
}
[IO.File]::WriteAllText("$OutFile.tmp", $out.ToString())
Move-Item -Force "$OutFile.tmp" $OutFile
$note = if ($Group) { "your group $Group" } else { "all houses (AskAH will work out which are yours next time you log in)" }
Log "wrote FeedData.lua: $got house(s), $note. /reload in game to load it."

# Blizzard game data (items, gear, recipes, quests) for AskAH and AskQuest.
# Separate background process (the feed doesn't wait for it); it only
# downloads everything when the game build changes, and skips if already running.
if ($env:ASKAH_CLOUD) { exit 0 }   # GitHub runs AskStatic.ps1 as its own step
try {
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $Here 'AskStatic.ps1') + '"'))
} catch { Log "static data: $($_.Exception.Message)" }
