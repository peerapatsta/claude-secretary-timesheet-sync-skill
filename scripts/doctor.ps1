<#
  Health check. Run this when the banner doesn't appear, the status line shows
  the wrong project, or hours come back empty:

      powershell -NoProfile -File "$env:USERPROFILE\.claude\timesheet-tools\scripts\doctor.ps1"

  Reports PASS/FAIL per component and prints the exact fix for each failure.
  Read-only - it never changes anything.
#>
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\tsconfig.ps1"

$fails = 0
function Check($name, $ok, $detail, $fix) {
  if ($ok) {
    Write-Host ("  PASS  {0,-22} {1}" -f $name, $detail) -ForegroundColor Green
  } else {
    Write-Host ("  FAIL  {0,-22} {1}" -f $name, $detail) -ForegroundColor Red
    if ($fix) { Write-Host ("        fix: {0}" -f $fix) -ForegroundColor Yellow }
    $script:fails++
  }
}

$claudeDir = Join-Path $env:USERPROFILE '.claude'
Write-Host "claude timesheet secretary - doctor" -ForegroundColor Cyan
Write-Host ""

# --- config ---
$cfgPath = Get-TsConfigPath
Check 'config file' (Test-Path $cfgPath) $cfgPath 'run install.ps1'
$cfg = Get-TsConfig

# --- junctions ---
foreach ($pair in @(
    @{ n = 'tools junction'; p = (Join-Path $claudeDir 'timesheet-tools') },
    @{ n = 'data junction';  p = (Join-Path $claudeDir 'timesheet-data') },
    @{ n = 'skill junction'; p = (Join-Path $claudeDir 'skills\timesheet') })) {
  $it = Get-Item $pair.p -Force -ErrorAction SilentlyContinue
  $ok = $it -and ($it.Attributes -band [IO.FileAttributes]::ReparsePoint)
  $detail = $pair.p
  if ($it) { $detail = "-> $($it.Target)" }
  Check $pair.n $ok $detail 'run install.ps1 again'
}

# --- data ---
$log = Join-Path $cfg.dataRoot 'activity-log.md'
Check 'dataRoot' (Test-Path $cfg.dataRoot) $cfg.dataRoot 'run install.ps1'
Check 'activity-log.md' (Test-Path $log) $log 'run install.ps1 (it seeds the template)'
$rawMine = Join-Path $cfg.dataRoot "raw\$($cfg.machine)"
$rawCount = 0
if (Test-Path $rawMine) { $rawCount = @(Get-ChildItem $rawMine -Filter *.jsonl).Count }
Check 'raw export' ($rawCount -gt 0) "$rawCount month file(s) in raw\$($cfg.machine)" `
      'python "$env:USERPROFILE\.claude\timesheet-tools\scripts\export_activity.py"'

# --- python ---
$py = Resolve-TsPython
$pyDetail = 'not found (Windows Store stub does not count)'
if ($py) { $pyDetail = $py.Exe }
Check 'python 3' ($null -ne $py) $pyDetail 'install Python 3 from python.org and tick "Add to PATH"'

# --- transcripts ---
$tx = Join-Path $claudeDir 'projects'
$txCount = 0
if (Test-Path $tx) { $txCount = @(Get-ChildItem $tx -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue).Count }
Check 'claude transcripts' ($txCount -gt 0) "$txCount session file(s)" 'use Claude Code for a while, then re-run'

# --- settings.json ---
$sp = Join-Path $claudeDir 'settings.json'
$settings = $null
if (Test-Path $sp) { $settings = (Get-Content -Raw -Encoding UTF8 $sp) | ConvertFrom-Json }
Check 'settings.json' ($null -ne $settings) $sp 'run install.ps1 (without -NoHook)'
if ($settings) {
  $allStart = @()
  foreach ($g in @($settings.hooks.SessionStart)) { foreach ($h in @($g.hooks)) { $allStart += $h.command } }
  Check 'SessionStart hook' (($allStart -join ' ') -like '*session-reminder.ps1*') `
        "$(@($allStart).Count) SessionStart hook(s)" 'run install.ps1 (without -NoHook)'
  Check 'statusLine' ($settings.statusLine.command -like '*statusline-command.ps1*') `
        "$($settings.statusLine.command)" 'run install.ps1, or point statusLine at scripts\statusline-command.ps1'
}

# --- sync ---
if ($cfg.sync.enabled) {
  $isRepo = (Test-Path (Join-Path $cfg.sync.repoRoot '.git'))
  Check 'sync repo' $isRepo $cfg.sync.repoRoot 'install.ps1 -DataRepo <path to your git clone>'
  if ($isRepo) {
    $remote = git -C $cfg.sync.repoRoot remote get-url origin 2>$null
    Check 'sync remote' ([bool]$remote) "$remote" 'git remote add origin <your private repo url>'
  }
  $task = Get-ScheduledTask -TaskName "ClaudeTimesheetSync-$($cfg.machine)" -ErrorAction SilentlyContinue
  Check 'hourly task' ($null -ne $task) "ClaudeTimesheetSync-$($cfg.machine)" 'run install.ps1 without -NoTask'
} else {
  Write-Host "  ----  sync                   off (local only)" -ForegroundColor DarkGray
}

# --- project rules ---
$here = (Get-Location).Path
$guess = Get-TsProjectName $here $cfg
Write-Host ""
Write-Host "resolved settings" -ForegroundColor Cyan
Write-Host "  machine   : $($cfg.machine)"
Write-Host "  timezone  : UTC+$($cfg.timezoneOffsetHours)"
Write-Host "  idle cap  : $($cfg.idleCapMinutes) min"
Write-Host "  projects  : $(@($cfg.projects).Count) rule(s)"
foreach ($r in @($cfg.projects)) { Write-Host "      $($r.name)  <- /$($r.match)/" }
Write-Host "  this dir  : $here  ->  [$guess]"

Write-Host ""
if ($fails -eq 0) {
  Write-Host "all checks passed." -ForegroundColor Green
} else {
  Write-Host "$fails check(s) failed - see the fixes above." -ForegroundColor Red
}
