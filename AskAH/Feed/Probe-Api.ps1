# Probe-Api.ps1
# One-off check of which Blizzard API endpoints answer for WoW: Forever.
# Uses the same config.json as the feed. Writes probe-results.txt next to this
# file: the status of each request and the start of each answer. Your client
# id and secret only go to oauth.battle.net and are never written to the file.

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Here 'probe-results.txt'
$cfg = Get-Content (Join-Path $Here 'config.json') -Raw | ConvertFrom-Json
$Region = ([string]$cfg.region).ToLower().Trim()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($cfg.clientId):$($cfg.clientSecret)"))
$tok = (Invoke-RestMethod -Method Post -Uri 'https://oauth.battle.net/token' -Headers @{ Authorization = "Basic $pair" } `
  -ContentType 'application/x-www-form-urlencoded' -Body 'grant_type=client_credentials').access_token

$lines = New-Object System.Collections.ArrayList
function W($s) { [void]$lines.Add($s); Write-Host $s }

function Probe([string]$path, [string]$ns, [int]$keep = 1500) {
  $sep = if ($path.Contains('?')) { '&' } else { '?' }
  $uri = "https://$Region.api.blizzard.com$path${sep}namespace=$ns-$Region&locale=en_US"
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 120
    $body = $r.Content
    W ("== 200 {0} [{1}] {2} bytes" -f $path, $ns, $body.Length)
    W ($body.Substring(0, [Math]::Min($keep, $body.Length)))
    W ''
    return ($body | ConvertFrom-Json)
  } catch {
    $code = 0; if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    W ("== {0} {1} [{2}]" -f $code, $path, $ns)
    W ''
    return $null
  }
}

W ("Probe run {0}, region {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $Region)
W ''

# --- items
Probe '/data/wow/item/2589' 'static-forever' | Out-Null          # Linen Cloth
Probe '/data/wow/item/720' 'static-forever' 300 | Out-Null       # reported 404
Probe '/data/wow/item/2770' 'static-forever' 800 | Out-Null       # Copper Ore
Probe '/data/wow/media/item/2589' 'static-forever' | Out-Null
Probe '/data/wow/item-class/index' 'static-forever' 600 | Out-Null
Probe '/data/wow/search/item?name.en_US=Linen%20Cloth&orderby=id' 'static-forever' 2500 | Out-Null
Probe '/data/wow/search/item?id=[2580,2600]&orderby=id&_pageSize=1000' 'static-forever' 2500 | Out-Null
Probe '/data/wow/item/2589' 'static-classic1x' 300 | Out-Null     # classic era namespace, for comparison
Probe '/data/wow/item/720' 'static-classic1x' 300 | Out-Null

# --- quests
Probe '/data/wow/quest/index' 'static-forever' 800 | Out-Null
Probe '/data/wow/quest/7' 'static-forever' 2500 | Out-Null
Probe '/data/wow/quest/490' 'static-forever' 2500 | Out-Null     # gold unknown in AskQuest
Probe '/data/wow/quest/65593' 'static-forever' 2500 | Out-Null   # Forever-new quest
Probe '/data/wow/quest/area/index' 'static-forever' 600 | Out-Null
Probe '/data/wow/quest/category/index' 'static-forever' 600 | Out-Null
Probe '/data/wow/search/quest?orderby=id' 'static-forever' 600 | Out-Null

# --- professions and recipes
$pi = Probe '/data/wow/profession/index' 'static-forever' 1500
if ($pi -and $pi.professions) {
  $p = $pi.professions | Where-Object { $_.name -eq 'Blacksmithing' } | Select-Object -First 1
  if (-not $p) { $p = $pi.professions[0] }
  $pd = Probe "/data/wow/profession/$($p.id)" 'static-forever' 1500
  if ($pd -and $pd.skill_tiers) {
    $st = Probe "/data/wow/profession/$($p.id)/skill-tier/$($pd.skill_tiers[0].id)" 'static-forever' 2000
    if ($st -and $st.categories) {
      $rid = $st.categories[0].recipes[0].id
      Probe "/data/wow/recipe/$rid" 'static-forever' 2500 | Out-Null
      Probe "/data/wow/media/recipe/$rid" 'static-forever' 500 | Out-Null
    }
  }
}

# --- other static data
Probe '/data/wow/spell/133' 'static-forever' 800 | Out-Null
Probe '/data/wow/creature/1' 'static-forever' 500 | Out-Null
Probe '/data/wow/search/creature?name.en_US=Hogger&orderby=id' 'static-forever' 800 | Out-Null
Probe '/data/wow/reputation-faction/index' 'static-forever' 500 | Out-Null
Probe '/data/wow/item-set/index' 'static-forever' 300 | Out-Null
Probe '/data/wow/mount/index' 'static-forever' 300 | Out-Null

# --- dynamic
Probe '/data/wow/ruleset/index' 'dynamic-forever' 800 | Out-Null
Probe '/data/wow/ruleset/1/auctions/' 'dynamic-forever' 1500 | Out-Null
Probe '/data/wow/token/index' 'dynamic-forever' 300 | Out-Null
Probe '/data/wow/realm/index' 'dynamic-forever' 300 | Out-Null

[IO.File]::WriteAllLines($Out, $lines)
Write-Host ''
Write-Host "Done. Results saved to $Out"
