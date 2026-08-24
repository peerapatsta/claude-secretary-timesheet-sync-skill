<#
  claude timesheet secretary - remove this machine's install.

  Removes the junctions, the hooks + statusLine from settings.json, and the
  hourly scheduled task. Your DATA IS NEVER TOUCHED: the log, raw\ and your data
  repo stay exactly where they are, and so does timesheet-config.json unless you
  pass -Purge.

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
    ... -File .\uninstall.ps1 -Purge     # also delete timesheet-config.json
#>
[CmdletBinding()]
param([switch]$Purge)
$ErrorActionPreference = 'Continue'

$claudeDir = Join-Path $env:USERPROFILE '.claude'
$cfgPath   = Join-Path $claudeDir 'timesheet-config.json'
$dataRoot  = ''
if (Test-Path $cfgPath) {
  try { $dataRoot = ((Get-Content -Raw -Encoding UTF8 $cfgPath) | ConvertFrom-Json).dataRoot } catch {}
}

Write-Host "claude timesheet secretary - uninstall" -ForegroundColor Cyan

# ---- junctions (remove the LINK only; Remove-Item on a junction does not
#      recurse into the target, but we use -Force without -Recurse to be sure)
foreach ($link in @(
    (Join-Path $claudeDir 'timesheet-tools'),
    (Join-Path $claudeDir 'timesheet-data'),
    (Join-Path $claudeDir 'skills\timesheet'))) {
  $it = Get-Item $link -Force -ErrorAction SilentlyContinue
  if (-not $it) { continue }
  if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    [IO.Directory]::Delete($it.FullName, $false)
    Write-Host "  removed junction $link" -ForegroundColor Green
  } else {
    Write-Host "  skipped $link (a real folder, not our junction)" -ForegroundColor Yellow
  }
}

# ---- settings.json
$sp = Join-Path $claudeDir 'settings.json'
if (Test-Path $sp) {
  Copy-Item $sp "$sp.bak" -Force
  $settings = (Get-Content -Raw -Encoding UTF8 $sp) | ConvertFrom-Json
  # `,$out` keeps an emptied list an ARRAY: a function that emits an empty array
  # returns nothing, which would land $null on the property instead of [].
  function Strip($events) {
    $out = @(@($events) | Where-Object {
      if ($null -eq $_) { return $false }
      $keep = $true
      foreach ($h in @($_.hooks)) {
        if ($h.command -match 'session-reminder\.ps1|sync-pull\.ps1|sync-push\.ps1') { $keep = $false }
      }
      $keep
    })
    return ,$out
  }
  if ($settings.hooks) {
    if ($settings.hooks.PSObject.Properties['SessionStart']) { $settings.hooks.SessionStart = Strip $settings.hooks.SessionStart }
    if ($settings.hooks.PSObject.Properties['SessionEnd'])   { $settings.hooks.SessionEnd   = Strip $settings.hooks.SessionEnd }
  }
  if ($settings.statusLine -and $settings.statusLine.command -like '*statusline-command.ps1*') {
    $settings.PSObject.Properties.Remove('statusLine')
    Write-Host "  removed statusLine" -ForegroundColor Green
  }
  [IO.File]::WriteAllText($sp, ($settings | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  Write-Host "  cleaned settings.json (backup: settings.json.bak)" -ForegroundColor Green
}

# ---- scheduled task
foreach ($t in @(Get-ScheduledTask -TaskName 'ClaudeTimesheetSync-*' -ErrorAction SilentlyContinue)) {
  Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
  Write-Host "  removed task $($t.TaskName)" -ForegroundColor Green
}
# The no-console-flash launcher the task ran through (see install.ps1 step 5).
$vbs = Join-Path $claudeDir 'timesheet-sync-hidden.vbs'
if (Test-Path $vbs) { Remove-Item $vbs -Force; Write-Host "  removed $vbs" -ForegroundColor Green }

# ---- config
if ($Purge -and (Test-Path $cfgPath)) {
  Remove-Item $cfgPath -Force
  Write-Host "  removed timesheet-config.json" -ForegroundColor Green
} elseif (Test-Path $cfgPath) {
  Write-Host "  kept    $cfgPath (use -Purge to delete)"
}

Write-Host ""
if ($dataRoot) { Write-Host "Your data is untouched at: $dataRoot" -ForegroundColor Cyan }
Write-Host "Restart Claude Code for the change to take effect."
