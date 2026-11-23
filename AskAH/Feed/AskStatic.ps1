# AskStatic.ps1
# Downloads WoW: Forever game data (items, gear stats, item sets, recipes,
# quest rewards) from Blizzard's API and writes it for the addons:
#   ..\BlizzData.lua             (AskAH: items, gear, sets, recipes)
#   ..\..\AskQuest\BlizzQuests.lua (AskQuest: quest gold, XP, reward items)
#
# AskAHFeed.ps1 calls this at the end of every run. It only downloads
# everything when Blizzard publishes a new game build (checked with one small
# request); otherwise it just looks up items that newly showed up on the AH.
# The first full run takes a few minutes. Run it by hand with -Force to
# rebuild everything.
#
# Uses the same config.json as the auction feed. Your client id and secret only
# go to oauth.battle.net.

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonDir = Split-Path -Parent $Here
$AddOnsDir = Split-Path -Parent $AddonDir
$Static = Join-Path $Here 'static'
$LogFile = Join-Path $Here 'feed.log'
$OutAH = Join-Path $AddonDir 'BlizzData.lua'
$QuestDataFile = Join-Path (Join-Path $AddOnsDir 'AskQuest') 'QuestData.lua'
$OutQuest = Join-Path (Join-Path $AddOnsDir 'AskQuest') 'BlizzQuests.lua'
$Conc = 12   # requests at once (Blizzard allows 100 per second)

trap { Log "stopped: $($_.Exception.Message)"; try { $Http.Dispose() } catch {}; if ($script:LockMine) { Remove-Item $Lock -ErrorAction SilentlyContinue }; exit 1 }

function Log($msg) {
  $line = "{0}  static: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

# Only one copy at a time (the feed starts this every 20 minutes).
$Lock = Join-Path $Here 'static.lock'
if ((Test-Path $Lock) -and ((Get-Date) - (Get-Item $Lock).LastWriteTime).TotalMinutes -lt 60) { exit 0 }
Set-Content -Path $Lock -Value $PID
$script:LockMine = $true

# ---------------------------------------------------------------- JSON
# Windows PowerShell: the .NET serializer (no 2 MB limit). PowerShell 7 on
# Linux (GitHub) doesn't have it and uses ConvertFrom-Json instead.
$Json = $null
try {
  Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
  $Json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $Json.MaxJsonLength = [int]::MaxValue
  $Json.RecursionLimit = 100
} catch { $Json = $null }
function Parse-Json([string]$t) { if ($Json) { return $Json.DeserializeObject($t) }; return ($t | ConvertFrom-Json -AsHashtable) }
function To-Json($o) { if ($Json) { return $Json.Serialize($o) }; return ($o | ConvertTo-Json -Depth 10 -Compress) }

# Walk a path in parsed JSON: G $obj 'a' 'b' 0 'c'
function G($o) {
  foreach ($k in $args) {
    if ($null -eq $o) { return $null }
    if ($k -is [int]) {
      if ($o -is [array] -and $k -lt $o.Count) { $o = $o[$k] } else { return $null }
    } elseif ($o -is [System.Collections.IDictionary]) {
      if ($o.ContainsKey($k)) { $o = $o[$k] } else { return $null }
    } else { return $null }
  }
  return $o
}
# Names come as a plain string or as { en_US = ..., de_DE = ... }
function Loc($v) {
  if ($v -is [System.Collections.IDictionary]) { if ($v.ContainsKey('en_US')) { return [string]$v['en_US'] }; return [string]@($v.Values)[0] }
  return [string]$v
}
function Arr($v) { if ($null -eq $v) { return @() }; return @($v) }

$Inv = [Globalization.CultureInfo]::InvariantCulture
function Num($v) { if ($null -eq $v) { return '' }; return ([double]$v).ToString('0.##', $Inv) }

function Load-Cache([string]$name) {
  $f = Join-Path $Static "$name.json"
  $h = @{}
  if (Test-Path $f) {
    try { $d = Parse-Json ([IO.File]::ReadAllText($f)); foreach ($k in $d.Keys) { $h[$k] = $d[$k] } } catch {}
  }
  return $h
}
function Save-Cache([string]$name, $h) {
  if (-not (Test-Path $Static)) { New-Item -ItemType Directory -Path $Static | Out-Null }
  $f = Join-Path $Static "$name.json"
  [IO.File]::WriteAllText("$f.tmp", (To-Json $h))
  Move-Item -Force "$f.tmp" $f
}

# ---------------------------------------------------------------- config, token
$cfg = Parse-Json ([IO.File]::ReadAllText((Join-Path $Here 'config.json')))
$ClientId = [string](G $cfg 'clientId'); $Secret = [string](G $cfg 'clientSecret')
$Region = ([string](G $cfg 'region')).ToLower().Trim()
if (-not $ClientId -or $ClientId -like 'PASTE*') { Log "config.json has no client id yet"; Remove-Item $Lock -ErrorAction SilentlyContinue; exit 1 }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 24
$Started = Get-Date

$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ClientId}:${Secret}"))
$tokResp = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://oauth.battle.net/token' `
  -Headers @{ Authorization = "Basic $pair" } -ContentType 'application/x-www-form-urlencoded' `
  -Body 'grant_type=client_credentials' -TimeoutSec 60
$Token = [string](G (Parse-Json $tokResp.Content) 'access_token')

Add-Type -AssemblyName System.Net.Http
$Http = New-Object System.Net.Http.HttpClient
$Http.Timeout = [TimeSpan]::FromSeconds(180)
$Http.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)

function Uri-For([string]$path, [string]$ns) {
  $sep = if ($path.Contains('?')) { '&' } else { '?' }
  return "https://$Region.api.blizzard.com$path${sep}namespace=$ns-$Region&locale=en_US"
}

# Fetch many paths, $Conc at a time. Returns @{ path = body } (body $null = 404).
# Paths that keep failing are left out, so the next run tries them again.
function Fetch-Many($paths, [string]$ns) {
  $res = @{}
  $tries = @{}
  $queue = New-Object System.Collections.Queue
  foreach ($p in $paths) { $queue.Enqueue([string]$p) }
  while ($queue.Count -gt 0) {
    $batch = @()
    while ($batch.Count -lt $Conc -and $queue.Count -gt 0) { $batch += $queue.Dequeue() }
    $tasks = @()
    foreach ($p in $batch) { $tasks += $Http.GetAsync((Uri-For $p $ns)) }
    # never wait forever: give the whole batch 4 minutes, and the run 45
    try { [void][Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks, 240000) } catch {}
    if (((Get-Date) - $Started).TotalMinutes -gt 45) { throw "took over 45 minutes; will continue next run" }
    $slow = $false
    for ($i = 0; $i -lt $batch.Count; $i++) {
      $p = $batch[$i]; $t = $tasks[$i]; $code = 0
      if ($t.IsCompleted -and -not ($t.IsFaulted -or $t.IsCanceled)) {
        $r = $t.Result; $code = [int]$r.StatusCode
        if ($code -eq 200) { $res[$p] = $r.Content.ReadAsStringAsync().Result }
        elseif ($code -eq 404) { $res[$p] = $null }
        $r.Dispose()
      }
      if ($code -eq 401 -or $code -eq 403) { throw "Blizzard refused the request ($code)" }
      if ($code -ne 200 -and $code -ne 404) {
        if ($code -eq 429) { $slow = $true }
        $tries[$p] = 1 + [int]$tries[$p]
        if ($tries[$p] -le 3) { $queue.Enqueue($p) }
      }
    }
    if ($slow) { Start-Sleep -Seconds 2 }
  }
  return $res
}

# ---------------------------------------------------------------- build check
Log "checking Blizzard's game data build"
$probe = Fetch-Many @('/data/wow/item/2589') 'static-forever'
$build = ''
$b = $probe['/data/wow/item/2589']
if ($b) { $m = [regex]::Match($b, 'namespace=(static-[^"&]+)'); if ($m.Success) { $build = $m.Groups[1].Value } }
if (-not $build) { Log "couldn't read the game build from Blizzard; skipping"; Remove-Item $Lock -ErrorAction SilentlyContinue; exit 1 }

$state = Load-Cache 'state'
if ($Force -or $state['build'] -ne $build) {
  if ($state['build']) { Log "new game build $build (was $($state['build'])): downloading everything again" }
  else { Log "first run for build ${build}: downloading items, gear, sets, recipes and quests (a few minutes)" }
  foreach ($n in @('items', 'gear', 'sets', 'recipes', 'quests', 'missing')) {
    $f = Join-Path $Static "$n.json"; if (Test-Path $f) { Remove-Item $f }
  }
  $state = @{ build = $build }
}
$changed = $false

$items = Load-Cache 'items'     # id -> "name|quality|ilvl|req|class|subclass|invtype|sell|buy|stack|src"
$gear = Load-Cache 'gear'       # id -> "armor|dps|speed|min|max|STAT:v,...|setId|classIds|bind"
$sets = Load-Cache 'sets'       # id -> { n, i, e }
$recipes = Load-Cache 'recipes' # id -> "name|profession|category|craftedId|qty|reagent:qty,..."
$quests = Load-Cache 'quests'   # id -> "xp|money|choice,...|fixed,...|typeId"
$missing = Load-Cache 'missing' # id -> 1 (no item data in either namespace)

$QUALITY = @{ POOR = 0; COMMON = 1; UNCOMMON = 2; RARE = 3; EPIC = 4; LEGENDARY = 5; ARTIFACT = 6; HEIRLOOM = 7 }
function Item-Line($d, [string]$src) {
  $name = (Loc (G $d 'name')) -replace '\|', '/'
  $q = $QUALITY[[string](G $d 'quality' 'type')]; if ($null -eq $q) { $q = 1 }
  $stack = if (G $d 'is_stackable') { 1 } else { 0 }
  return '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f $name, $q, (G $d 'level'), (G $d 'required_level'),
    (G $d 'item_class' 'id'), (G $d 'item_subclass' 'id'), (G $d 'inventory_type' 'type'),
    (G $d 'sell_price'), (G $d 'purchase_price'), $stack, $src
}
$NOGEAR = @{ NON_EQUIP = 1; BAG = 1; QUIVER = 1; AMMO = 1; BODY = 1; TABARD = 1 }
function Is-Gear([string]$line) {
  $p = $line.Split('|')
  return (($p[4] -eq '2' -or $p[4] -eq '4') -and -not $NOGEAR.ContainsKey($p[6]))
}

# ---------------------------------------------------------------- 1. items (bulk search)
if (-not $state['items']) {
  $windows = @()
  for ($a = 1; $a -lt 40000; $a += 4000) { $windows += , @($a, ($a + 3999)) }
  for ($a = 40000; $a -lt 300000; $a += 20000) { $windows += , @($a, ($a + 19999)) }
  $paths = $windows | ForEach-Object { "/data/wow/search/item?id=[$($_[0]),$($_[1])]&orderby=id&_pageSize=1000&_page=1" }
  $pages = Fetch-Many $paths 'static-forever'
  $more = @()
  foreach ($p in $paths) {
    if (-not $pages.ContainsKey($p)) { throw "item search failed for $p" }
    if (-not $pages[$p]) { continue }
    $j = Parse-Json $pages[$p]
    $pc = [int](G $j 'pageCount')
    for ($n = 2; $n -le $pc; $n++) { $more += ($p -replace '_page=1$', "_page=$n") }
    $pages[$p] = $j
  }
  if ($more.Count) {
    $extra = Fetch-Many $more 'static-forever'
    foreach ($p in $more) { if (-not $extra[$p]) { throw "item search failed for $p" }; $pages[$p] = Parse-Json $extra[$p] }
  }
  foreach ($j in $pages.Values) {
    foreach ($r in (Arr (G $j 'results'))) {
      $d = G $r 'data'; $id = G $d 'id'
      if ($id) { $items[[string]$id] = Item-Line $d 'f' }
    }
  }
  $state['items'] = 1; $changed = $true
  Save-Cache 'items' $items; Save-Cache 'state' $state
  Log ("items: {0} from Forever's item list" -f $items.Count)
}

# ---------------------------------------------------------------- 2. recipes
if (-not $state['recipes']) {
  $idx = Fetch-Many @('/data/wow/profession/index') 'static-forever'
  $profs = Arr (G (Parse-Json $idx['/data/wow/profession/index']) 'professions')
  $pp = Fetch-Many ($profs | ForEach-Object { "/data/wow/profession/$(G $_ 'id')" }) 'static-forever'
  $tierPaths = @(); $tierProf = @{}
  foreach ($pr in $profs) {
    $profId = G $pr 'id'; $body = $pp["/data/wow/profession/$profId"]; if (-not $body) { continue }
    foreach ($t in (Arr (G (Parse-Json $body) 'skill_tiers'))) {
      $tp = "/data/wow/profession/$profId/skill-tier/$(G $t 'id')"; $tierPaths += $tp; $tierProf[$tp] = Loc (G $pr 'name')
    }
  }
  $tiers = Fetch-Many $tierPaths 'static-forever'
  $recipeMeta = @{}
  foreach ($tp in $tierPaths) {
    if (-not $tiers[$tp]) { continue }
    foreach ($c in (Arr (G (Parse-Json $tiers[$tp]) 'categories'))) {
      foreach ($rc in (Arr (G $c 'recipes'))) { $recipeMeta[[string](G $rc 'id')] = @($tierProf[$tp], (Loc (G $c 'name'))) }
    }
  }
  $rb = Fetch-Many ($recipeMeta.Keys | ForEach-Object { "/data/wow/recipe/$_" }) 'static-forever'
  foreach ($rid in $recipeMeta.Keys) {
    $body = $rb["/data/wow/recipe/$rid"]; if (-not $body) { continue }
    $r = Parse-Json $body
    $reag = (Arr (G $r 'reagents') | ForEach-Object { "$(G $_ 'reagent' 'id'):$(G $_ 'quantity')" }) -join ','
    $qty = G $r 'crafted_quantity' 'value'; if (-not $qty) { $qty = G $r 'crafted_quantity' 'minimum' }; if (-not $qty) { $qty = 1 }
    $name = (Loc (G $r 'name')) -replace '\|', '/'
    $recipes[$rid] = '{0}|{1}|{2}|{3}|{4}|{5}' -f $name, $recipeMeta[$rid][0], (($recipeMeta[$rid][1]) -replace '\|', '/'),
      (G $r 'crafted_item' 'id'), (Num $qty), $reag
  }
  $state['recipes'] = 1; $changed = $true
  Save-Cache 'recipes' $recipes; Save-Cache 'state' $state
  Log ("recipes: {0} in {1} professions" -f $recipes.Count, $profs.Count)
}

# ---------------------------------------------------------------- 3. quests (AskQuest's quest list)
if (-not $state['quests'] -and (Test-Path $QuestDataFile)) {
  $ids = @{}
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText($QuestDataFile), '(?m)^\[(\d+)\]=\{"')) { $ids[$m.Groups[1].Value] = 1 }
  $todo = @($ids.Keys | Where-Object { -not $quests.ContainsKey($_) })
  for ($s = 0; $s -lt $todo.Count; $s += 600) {
    $chunk = $todo[$s..([Math]::Min($s + 599, $todo.Count - 1))]
    $qb = Fetch-Many ($chunk | ForEach-Object { "/data/wow/quest/$_" }) 'static-forever'
    foreach ($qid in $chunk) {
      $p = "/data/wow/quest/$qid"
      if (-not $qb.ContainsKey($p)) { continue }
      if (-not $qb[$p]) { $quests[$qid] = ''; continue }
      $q = Parse-Json $qb[$p]
      $rw = G $q 'rewards'
      $choice = (Arr (G $rw 'items' 'choice_of') | ForEach-Object { G $_ 'item' 'id' }) -join ','
      $fixed = (Arr (G $rw 'items' 'items') | ForEach-Object { G $_ 'item' 'id' }) -join ','
      $money = G $rw 'money' 'value'; if ($null -eq $money) { $money = 0 }
      $quests[$qid] = '{0}|{1}|{2}|{3}|{4}' -f (G $rw 'experience'), $money, $choice, $fixed, (G $q 'type' 'id')
    }
    Save-Cache 'quests' $quests
  }
  if (@($ids.Keys | Where-Object { -not $quests.ContainsKey($_) }).Count -eq 0) { $state['quests'] = 1 }
  $changed = $true
  Save-Cache 'state' $state
  Log ("quests: {0} of {1} found" -f @($quests.Values | Where-Object { $_ }).Count, $ids.Count)
}

# ---------------------------------------------------------------- 4. items we need but Forever's list lacks
# AH items, quest rewards and reagents; Blizzard's Classic Era data has most of them.
$need = @{}
foreach ($f in (Get-ChildItem -Path (Join-Path $Here 'state') -Filter 'house-*.json' -ErrorAction SilentlyContinue)) {
  # only the item lists (the "snap" section is keyed by auction id, not item id)
  try { $hs = Parse-Json ([IO.File]::ReadAllText($f.FullName)) } catch { continue }
  foreach ($sec in @('items', 'hist')) {
    $d = G $hs $sec
    if ($d -is [System.Collections.IDictionary]) { foreach ($k in $d.Keys) { if ($k -match '^\d{1,6}$') { $need[$k] = 1 } } }
  }
}
foreach ($v in $quests.Values) { if ($v) { $p = ([string]$v).Split('|'); foreach ($x in ($p[2] + ',' + $p[3]).Split(',')) { if ($x) { $need[$x] = 1 } } } }
foreach ($v in $recipes.Values) {
  $p = ([string]$v).Split('|'); if ($p[3]) { $need[$p[3]] = 1 }
  foreach ($x in $p[5].Split(',')) { $rid = $x.Split(':')[0]; if ($rid) { $need[$rid] = 1 } }
}
$lookup = @($need.Keys | Where-Object { -not $items.ContainsKey($_) -and -not $missing.ContainsKey($_) })
if ($lookup.Count) {
  Log ("items: looking up {0} new ones" -f $lookup.Count)
  $fb = Fetch-Many ($lookup | ForEach-Object { "/data/wow/item/$_" }) 'static-forever'
  $still = @()
  foreach ($id in $lookup) {
    $p = "/data/wow/item/$id"
    if ($fb[$p]) { $items[$id] = Item-Line (Parse-Json $fb[$p]) 'f' } elseif ($fb.ContainsKey($p)) { $still += $id }
  }
  if ($still.Count) {
    $cb = Fetch-Many ($still | ForEach-Object { "/data/wow/item/$_" }) 'static-classic1x'
    foreach ($id in $still) {
      $p = "/data/wow/item/$id"
      if ($cb[$p]) { $items[$id] = Item-Line (Parse-Json $cb[$p]) 'c' } elseif ($cb.ContainsKey($p)) { $missing[$id] = 1 }
    }
  }
  Save-Cache 'items' $items; Save-Cache 'missing' $missing
  $changed = $true
  Log ("items: looked up {0} new ones ({1} from Classic Era data, {2} not found)" -f $lookup.Count, @($items.Values | Where-Object { $_.EndsWith('|c') }).Count, $missing.Count)
}

# ---------------------------------------------------------------- 5. gear stats (one request per item)
$STAT = @{ STRENGTH = 'STR'; AGILITY = 'AGI'; STAMINA = 'STA'; INTELLECT = 'INT'; SPIRIT = 'SPI'
  ATTACK_POWER = 'AP'; RANGED_ATTACK_POWER = 'RAP'; SPELL_POWER = 'SP'; CRIT_RATING = 'CRIT'; HIT_RATING = 'HIT'
  DEFENSE_SKILL_RATING = 'DEFENSE'; DODGE_RATING = 'DODGE'; PARRY_RATING = 'PARRY'; BLOCK_RATING = 'BLOCK'
  BLOCK_VALUE = 'BLOCKVALUE'; MANA_REGENERATION = 'MP5'; SPELL_HEALING_DONE = 'HEAL'; SPELL_DAMAGE_DONE = 'SP' }
# Classic items put many stats in "Equip:" effects instead.
$SPELLSTAT = @(
  @('chance to hit by (\d+)%', 'HIT'), @('chance to get a critical strike by (\d+)%', 'CRIT'),
  @('^\+(\d+) ranged Attack Power', 'RAP'), @('^\+(\d+) Attack Power', 'AP'),
  @('damage and healing done by magical spells and effects by up to (\d+)', 'SP'),
  @('healing done by spells and effects by up to (\d+)', 'HEAL'), @('Restores (\d+) mana per 5 sec', 'MP5'),
  @('block value of your shield by (\d+)', 'BLOCKVALUE'), @('Increased Defense \+(\d+)', 'DEFENSE'),
  @('chance to dodge an attack by (\d+)%', 'DODGE'), @('chance to parry an attack by (\d+)%', 'PARRY'),
  @('chance to block attacks with a shield by (\d+)%', 'BLOCK'))
function Gear-Line($d) {
  $pv = G $d 'preview_item'
  $st = [ordered]@{}
  foreach ($s in (Arr (G $pv 'stats'))) {
    if (G $s 'is_negated') { continue }
    $t = [string](G $s 'type' 'type'); $k = $STAT[$t]; if (-not $k) { $k = $t }
    $st[$k] = [int]$st[$k] + [int](G $s 'value')
  }
  foreach ($sp in (Arr (G $pv 'spells'))) {
    $desc = [string](G $sp 'description')
    foreach ($rule in $SPELLSTAT) {
      $m = [regex]::Match($desc, $rule[0]); if ($m.Success) { $st[$rule[1]] = [int]$st[$rule[1]] + [int]$m.Groups[1].Value; break }
    }
  }
  $stats = ($st.Keys | ForEach-Object { "${_}:$($st[$_])" }) -join ','
  $classes = (Arr (G $pv 'requirements' 'playable_classes' 'links') | ForEach-Object { G $_ 'id' }) -join ','
  $bind = @{ ON_ACQUIRE = 1; ON_EQUIP = 2; ON_USE = 3; QUEST = 4 }[[string](G $pv 'binding' 'type')]
  return '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f (G $pv 'armor' 'value'), (Num (G $pv 'weapon' 'dps' 'value')),
    (G $pv 'weapon' 'attack_speed' 'value'), (G $pv 'weapon' 'damage' 'min_value'), (G $pv 'weapon' 'damage' 'max_value'),
    $stats, (G $pv 'set' 'item_set' 'id'), $classes, $bind
}
# Classic Era items: an empty entry from an earlier run means it was only tried on Forever.
foreach ($k in @($gear.Keys)) { if ($gear[$k] -eq '' -and $items.ContainsKey($k) -and $items[$k].EndsWith('|c')) { $gear.Remove($k) } }
$todo = @($items.Keys | Where-Object { -not $gear.ContainsKey($_) -and (Is-Gear $items[$_]) })
if ($todo.Count) {
  Log ("gear: reading stats for {0} items" -f $todo.Count)
  for ($s = 0; $s -lt $todo.Count; $s += 1000) {
    $chunk = $todo[$s..([Math]::Min($s + 999, $todo.Count - 1))]
    foreach ($ns in @('static-forever', 'static-classic1x')) {
      $isC = ($ns -eq 'static-classic1x')
      $ids = @($chunk | Where-Object { -not $gear.ContainsKey($_) -and ($items[$_].EndsWith('|c') -eq $isC) })
      if (-not $ids.Count) { continue }
      $gb = Fetch-Many ($ids | ForEach-Object { "/data/wow/item/$_" }) $ns
      foreach ($id in $ids) { $b = $gb["/data/wow/item/$id"]; if ($b) { $gear[$id] = Gear-Line (Parse-Json $b) } elseif ($gb.ContainsKey("/data/wow/item/$id")) { $gear[$id] = '-' } }
    }
    Save-Cache 'gear' $gear
  }
  $changed = $true
}

# ---------------------------------------------------------------- 6. item sets
if (-not $state['sets']) {
  $si = Fetch-Many @('/data/wow/item-set/index') 'static-forever'
  $list = Arr (G (Parse-Json $si['/data/wow/item-set/index']) 'item_sets')
  $sb = Fetch-Many ($list | ForEach-Object { "/data/wow/item-set/$(G $_ 'id')" }) 'static-forever'
  foreach ($e in $list) {
    $sid = [string](G $e 'id'); $b = $sb["/data/wow/item-set/$sid"]; if (-not $b) { continue }
    $j = Parse-Json $b
    $sets[$sid] = @{ n = (Loc (G $j 'name')); i = @(Arr (G $j 'items') | ForEach-Object { G $_ 'id' })
      e = @(Arr (G $j 'effects') | ForEach-Object { "$(G $_ 'required_count'):$(Loc (G $_ 'display_string'))" }) }
  }
  $state['sets'] = 1; $changed = $true
  Save-Cache 'sets' $sets; Save-Cache 'state' $state
  Log ("item sets: {0}" -f $sets.Count)
}

# ---------------------------------------------------------------- write the Lua files
function LStr([string]$s) {
  return '"' + ($s -replace '\\', '\\' -replace '"', '\"' -replace "`r", '' -replace "`n", '\n') + '"'
}
# One function per 3000 entries keeps each chunk well under Lua's constant limit.
function Write-Table($sb, [string]$target, $h, [scriptblock]$fmt) {
  $keys = @($h.Keys | Where-Object { $h[$_] -and $h[$_] -ne '-' } | Sort-Object { [int]$_ })
  for ($s = 0; $s -lt $keys.Count; $s += 3000) {
    [void]$sb.AppendLine("(function() local T = $target")
    foreach ($k in $keys[$s..([Math]::Min($s + 2999, $keys.Count - 1))]) { [void]$sb.AppendLine("T[$k]=" + (& $fmt $h[$k])) }
    [void]$sb.AppendLine('end)();')   # the ; matters: Lua 5.1 rejects a new line starting with ( after a call
  }
}

$needWrite = $changed -or -not (Test-Path $OutAH) -or ((Get-Item $OutAH).Length -lt 1000)
if ($needWrite) {
  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('-- BlizzData.lua: written by Feed\AskStatic.ps1 from Blizzard''s game data API. Do not edit.')
  [void]$sb.AppendLine("AskAHBlizz = { v = 1, build = `"$build`", t = $stamp, items = {}, gear = {}, sets = {}, recipes = {} }")
  Write-Table $sb 'AskAHBlizz.items' $items { param($v) LStr $v }
  Write-Table $sb 'AskAHBlizz.gear' $gear { param($v) LStr $v }
  Write-Table $sb 'AskAHBlizz.recipes' $recipes { param($v) LStr $v }
  Write-Table $sb 'AskAHBlizz.sets' $sets { param($v)
    '{ n = ' + (LStr (G $v 'n')) + ', i = {' + ((Arr (G $v 'i')) -join ',') + '}, e = {' + ((Arr (G $v 'e') | ForEach-Object { LStr $_ }) -join ',') + '} }' }
  [IO.File]::WriteAllText("$OutAH.tmp", $sb.ToString())
  Move-Item -Force "$OutAH.tmp" $OutAH

  if ((Test-Path (Split-Path -Parent $OutQuest)) -and $quests.Count) {
    $sq = New-Object System.Text.StringBuilder
    [void]$sq.AppendLine('-- BlizzQuests.lua: written by AskAH\Feed\AskStatic.ps1 from Blizzard''s game data API. Do not edit.')
    [void]$sq.AppendLine("AskQuestBlizz = { v = 1, build = `"$build`", t = $stamp, quests = {} }")
    Write-Table $sq 'AskQuestBlizz.quests' $quests { param($v) LStr $v }
    [IO.File]::WriteAllText("$OutQuest.tmp", $sq.ToString())
    Move-Item -Force "$OutQuest.tmp" $OutQuest
  }
  Log ("wrote BlizzData.lua ({0} items, {1} gear, {2} recipes, {3} sets) and BlizzQuests.lua ({4} quests)" -f
    $items.Count, @($gear.Values | Where-Object { $_ -and $_ -ne '-' }).Count, $recipes.Count, $sets.Count, @($quests.Values | Where-Object { $_ }).Count)
}
$Http.Dispose()
Log ("done in {0:0} s" -f ((Get-Date) - $Started).TotalSeconds)
Remove-Item $Lock -ErrorAction SilentlyContinue
