<#
  SessionStart hook for the timesheet secretary.

  Emits two things:
    - systemMessage    : the banner the USER sees immediately at session start
    - additionalContext : the model-only instruction Claude acts on once you
                          send your first message

  All per-user values (log path, last submitted date) come from
  timesheet-config.json, so this file is identical on every machine.
#>
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\tsconfig.ps1"

$today = Get-Date -Format 'yyyy-MM-dd'
$cfg   = Get-TsConfig
$log   = Join-Path $cfg.dataRoot 'activity-log.md'
# Point at the junction, not $PSScriptRoot: the skill tells Claude to use this
# same path, and a single spelling keeps the two from drifting apart.
$setPj = Join-Path $env:USERPROFILE '.claude\timesheet-tools\scripts\set-project.ps1'
if (-not (Test-Path $setPj)) { $setPj = Join-Path $PSScriptRoot 'set-project.ps1' }

$backfill = ''
if ($cfg.lastSubmitted) {
  $backfill = " The last submitted timesheet was $($cfg.lastSubmitted) - if days are unlogged since then, offer once to backfill."
}

# Daily "your tools are out of date" check. Self-throttling and time-boxed, and
# it returns nothing on any failure, so a bad network can't delay session start.
$update = ''
try { $update = (& "$PSScriptRoot\check-update.ps1" | Select-Object -First 1) } catch {}
$updateMsg    = ''
$updateBanner = ''
if ($update) {
  $updateMsg    = " $update Mention this to the user once, then carry on."
  $updateBanner = "   ** $update`n"
}

$msg = @"
[TIMESHEET SECRETARY ACTIVE] Today is $today. Before doing other work this session, use the 'timesheet' skill: confirm the auto-guessed project shown in the status line (e.g. [PROJ?]) and ask the user "Working on <project> - what's the task?" (skip if they already said so in their first message). Once confirmed, pin it with `powershell -NoProfile -File "$setPj" <NAME>` (step S) so the status line drops the '?'. Track time spent, and when a task looks finished ask "Is it done?" before marking it Done with hours. Log every task as a row in $log.$backfill$updateMsg
"@

# IMPORTANT: keep this banner ASCII-only. Windows PowerShell writes stdout in the
# OEM codepage, so emoji / box-drawing chars reach Claude Code as literal '?'.
# Prominence comes from CAPS + '='/'!' rules + short lines, not fancy glyphs.
$rule = '=' * 52
$banner = @"
$rule
   TIMESHEET LOG  -  $today
$rule
   >> What are you working on RIGHT NOW, and on which PROJECT?
      (my guess is [NAME?] in the status line below)
   >> Tell me the task and I'll pin the project - the '?' drops off.
   !! Nothing is logged until you say - don't leave today blank.
$updateBanner$rule
"@

$payload = @{
  systemMessage      = $banner
  hookSpecificOutput = @{
    hookEventName     = 'SessionStart'
    additionalContext = $msg
  }
}

$payload | ConvertTo-Json -Compress -Depth 5
