<#
  Is there a newer version of the timesheet tools upstream?

  Prints ONE ASCII line to stdout when the local clone is behind, and nothing at
  all otherwise - so a caller can splice the result straight into a banner:

      $notice = & check-update.ps1

  Driven by the `update` block in timesheet-config.json:

      "update": {
        "enabled": true,
        "repo": "https://github.com/you/claude-secretary-timesheet-sync-skill.git",
        "branch": "main",
        "checkEveryHours": 24
      }

  The network call is throttled to once per checkEveryHours; between checks the
  cached verdict is replayed from ~\.claude\timesheet-update-check.json, so the
  notice keeps nagging every session until you actually update, without hitting
  the network every time. -Force ignores the throttle.

  Never throws and never blocks: ls-remote runs in a job capped at -TimeoutSec,
  and any failure (offline, VPN, auth prompt) just means "no notice this time".
#>
[CmdletBinding()]
param(
  [switch]$Force,
  [int]$TimeoutSec = 6
)
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\tsconfig.ps1"

$cfg = Get-TsConfig
$upd = $cfg.update
if (-not $upd -or -not $upd.enabled) { return }

$tools = $cfg.toolsRoot
if (-not $tools) { $tools = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path (Join-Path $tools '.git'))) { return }   # not a clone - nothing to update

$branch = if ($upd.branch) { $upd.branch } else { 'main' }
$repo   = $upd.repo
if (-not $repo) { $repo = (& git -C $tools remote get-url origin) }
if (-not $repo) { return }

$every = if ($upd.checkEveryHours) { [double]$upd.checkEveryHours } else { 24 }
$stamp = Join-Path $env:USERPROFILE '.claude\timesheet-update-check.json'

function Read-Stamp {
  if (-not (Test-Path $stamp)) { return $null }
  try { return (Get-Content -Raw -Encoding UTF8 $stamp) | ConvertFrom-Json } catch { return $null }
}
function Write-Stamp($remoteSha) {
  $obj = [PSCustomObject]@{
    lastCheck = (Get-Date).ToString('o')
    branch    = $branch
    remote    = $remoteSha
  }
  $json = $obj | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($stamp, $json, (New-Object Text.UTF8Encoding($false)))
}

# The local side is cheap and always current, so it is read on every call: an
# update applied by hand must clear the notice immediately, not at the next
# scheduled network check.
$localSha = (& git -C $tools rev-parse HEAD)
if (-not $localSha) { return }

$prev      = Read-Stamp
$remoteSha = $null
$fresh     = $false
if (-not $Force -and $prev -and $prev.lastCheck -and $prev.branch -eq $branch) {
  $age = (Get-Date) - [datetime]::Parse($prev.lastCheck)
  if ($age.TotalHours -lt $every) { $remoteSha = $prev.remote }
}

if (-not $remoteSha) {
  # A hung ls-remote (dead VPN, credential prompt) would otherwise stall every
  # session start until the hook's own timeout fires.
  $env:GIT_TERMINAL_PROMPT = '0'
  $job = Start-Job -ScriptBlock {
    param($r, $b)
    $env:GIT_TERMINAL_PROMPT = '0'
    (& git ls-remote --heads $r "refs/heads/$b") 2>$null
  } -ArgumentList $repo, $branch
  $done = Wait-Job $job -Timeout $TimeoutSec
  if ($done) { $out = Receive-Job $job }
  Remove-Job $job -Force
  if (-not $out) { return }
  $remoteSha = (($out | Select-Object -First 1) -split '\s+')[0]
  if ($remoteSha -notmatch '^[0-9a-f]{40}$') { return }
  $fresh = $true
  Write-Stamp $remoteSha
}

if ($remoteSha -eq $localSha) { return }

# Behind, ahead or diverged? Only nag when the remote commit is genuinely one we
# do not have - a local-only patch on top of an up-to-date clone is not "behind".
& git -C $tools cat-file -e "$remoteSha^{commit}" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { return }

$short = $remoteSha.Substring(0, 7)
$when  = if ($fresh) { 'just checked' } else { 'cached' }
"UPDATE AVAILABLE: timesheet tools - $branch is at $short upstream ($when). Run: git -C `"$tools`" pull --ff-only  then re-run install.ps1"
