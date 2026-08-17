<#
  claude timesheet secretary - per-machine installer.

  Wires this clone into Claude Code on THIS machine:

    1. Junctions (no admin needed) so every path is identical everywhere:
         ~\.claude\timesheet-tools   -> <this repo>
         ~\.claude\timesheet-data    -> your data folder
         ~\.claude\skills\timesheet  -> <this repo>\skills\timesheet
    2. Writes ~\.claude\timesheet-config.json (existing settings are PRESERVED)
    3. Seeds your data folder (activity-log.md, raw\, .gitignore) - and if a
       previous install pointed somewhere else, MOVES the existing log + raw\
       exports across, so "start local, add -DataRepo later" keeps your history
    4. Merges hooks + statusLine into ~\.claude\settings.json (idempotent + backup)
    5. Optional: hourly Scheduled Task running sync-push.ps1
    6. Runs an initial activity export

  Re-runnable. Any real folder it would replace with a junction is renamed to
  *.pre-timesheet.bak first (never deleted).

  Usage
    # local only - log lives in <Documents>\claude-timesheet-data
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

    # keep your log in your own PRIVATE git repo (already cloned)
    ... -File .\install.ps1 -DataRepo "C:\src\my-timesheet-data"

    # ...or let the installer clone it for you
    ... -File .\install.ps1 -DataRepo "https://github.com/you/my-timesheet-data.git"

    # other switches
    -DataDir <path>   plain folder for the log, no git       (mutually exclusive with -DataRepo)
    -DataPath <path>  where to clone when -DataRepo is a URL
    -Machine <name>   machine id for raw\<machine>\ (default: $env:COMPUTERNAME)
    -NoTask           skip the hourly scheduled task
    -NoHook           don't touch settings.json
    -Plan             print what would happen, change nothing
#>
[CmdletBinding()]
param(
  [string]$DataRepo,
  [string]$DataDir,
  [string]$DataPath,
  [string]$Machine,
  [switch]$NoTask,
  [switch]$NoHook,
  [switch]$Plan
)
$ErrorActionPreference = 'Stop'

$tools     = $PSScriptRoot
$scripts   = Join-Path $tools 'scripts'
$claudeDir = Join-Path $env:USERPROFILE '.claude'
if (-not $Machine) { $Machine = $env:COMPUTERNAME }
if ($DataRepo -and $DataDir) { throw "-DataRepo and -DataDir are mutually exclusive" }

# $ErrorActionPreference = 'Stop' + a native command's redirected stderr =
# NativeCommandError, which aborts the install over a harmless git warning
# ("LF will be replaced by CRLF"). Route every git call through here.
function Invoke-Git {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  $out = & git @args 2>&1 | ForEach-Object { $_.ToString() }
  $ErrorActionPreference = $prev
  return $out
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

# Trailing slashes, case and 8.3 short names ("WINDOW~1") make raw string
# comparison of junction targets unreliable, so normalize before comparing.
function Norm-Path([string]$p) {
  if (-not $p) { return '' }
  try { $p = [IO.Path]::GetFullPath($p) } catch {}
  return $p.TrimEnd('\', '/').ToLowerInvariant()
}

function New-JunctionSafe {
  param([string]$Link, [string]$Target)
  if (-not (Test-Path $Target)) { throw "junction target missing: $Target" }
  $item = Get-Item $Link -Force -ErrorAction SilentlyContinue
  if ($item) {
    $isLink = $item.Attributes -band [IO.FileAttributes]::ReparsePoint
    if ($isLink) {
      $cur = @($item.Target)[0]
      if ((Norm-Path $cur) -eq (Norm-Path $Target)) { Write-Host "  ok     $Link (already linked)"; return }
      # Remove-Item on a junction can throw NullReferenceException in PS 5.1;
      # Directory.Delete($p, $false) removes the link and never the target.
      [IO.Directory]::Delete($item.FullName, $false)
      Write-Host "  relink $Link (was -> $cur)"
    } else {
      $bak = "$Link.pre-timesheet.bak"
      if (Test-Path $bak) { $bak = "$Link.pre-timesheet.$(Get-Date -Format yyyyMMddHHmmss).bak" }
      Move-Item $Link $bak
      Write-Host "  moved  $Link -> $bak (real folder preserved)" -ForegroundColor Yellow
    }
  }
  $parent = Split-Path -Parent $Link
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
  Write-Host "  link   $Link -> $Target" -ForegroundColor Green
}

# Move an existing log + raw exports to a new dataRoot. The upgrade path
# "start local, add -DataRepo once you get a second machine" is the one people
# actually walk, and without this the installer would seed a blank log in the
# repo and silently orphan the real one.
function Move-TsData {
  param([string]$From, [string]$To)
  $fromLog = Join-Path $From 'activity-log.md'
  $fromRaw = Join-Path $From 'raw'
  if (-not (Test-Path $fromLog) -and -not (Test-Path $fromRaw)) { return $false }

  $toLog = Join-Path $To 'activity-log.md'
  if (Test-Path $toLog) {
    Write-Host "  ! an older log exists at $From" -ForegroundColor Yellow
    Write-Host "    and $To already has activity-log.md - NOT merged automatically." -ForegroundColor Yellow
    Write-Host "    Merge the rows by hand, then delete the old folder." -ForegroundColor Yellow
    return $false
  }

  if (Test-Path $fromLog) {
    Move-Item $fromLog $toLog
    Write-Host "  moved  activity-log.md   (from $From)" -ForegroundColor Green
  }
  if (Test-Path $fromRaw) {
    foreach ($m in @(Get-ChildItem $fromRaw -Directory -ErrorAction SilentlyContinue)) {
      $dest = Join-Path (Join-Path $To 'raw') $m.Name
      New-Item -ItemType Directory -Force -Path $dest | Out-Null
      foreach ($f in @(Get-ChildItem $m.FullName -Filter *.jsonl -ErrorAction SilentlyContinue)) {
        $t = Join-Path $dest $f.Name
        # Never clobber: the destination copy may already hold sessions this one
        # doesn't (another machine pushed them).
        if (Test-Path $t) { Write-Host "  kept   raw\$($m.Name)\$($f.Name) (already in the new location)" }
        else { Move-Item $f.FullName $t; Write-Host "  moved  raw\$($m.Name)\$($f.Name)" -ForegroundColor Green }
      }
    }
  }
  # activity-log.csv / .xlsx are derived - regenerate them, don't move them.
  Write-Host "  old folder left in place (now empty of log data): $From"
  return $true
}

# ---- resolve the data location ---------------------------------------------
$syncEnabled = $false
$repoRoot    = ''

# Read the PREVIOUS dataRoot before step 3 overwrites the config, so step 1 can
# migrate out of it.
$prevDataRoot = ''
$prevCfgPath  = Join-Path $claudeDir 'timesheet-config.json'
if (Test-Path $prevCfgPath) {
  try { $prevDataRoot = ((Get-Content -Raw -Encoding UTF8 $prevCfgPath) | ConvertFrom-Json).dataRoot } catch {}
}

if ($DataRepo) {
  $syncEnabled = $true
  if ($DataRepo -match '^(https?://|git@|ssh://)') {
    $name = [IO.Path]::GetFileNameWithoutExtension(($DataRepo -split '[/:]')[-1])
    if ($DataPath) { $repoRoot = $DataPath }
    else { $repoRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) $name }
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
      Write-Host "cloning $DataRepo -> $repoRoot"
      if (-not $Plan) { Invoke-Git clone $DataRepo $repoRoot | ForEach-Object { Write-Host "  $_" } }
    } else {
      Write-Host "using existing clone at $repoRoot"
    }
  } else {
    $repoRoot = (Resolve-Path $DataRepo -ErrorAction SilentlyContinue).Path
    if (-not $repoRoot) { $repoRoot = $DataRepo }
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
      throw "-DataRepo '$repoRoot' is not a git repo. Clone/init it first, or use -DataDir for a plain folder."
    }
  }
  $dataRoot = Join-Path $repoRoot 'timesheet'
} elseif ($DataDir) {
  $dataRoot = $DataDir
} else {
  $dataRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'claude-timesheet-data'
}

Write-Host "claude timesheet secretary - install on $Machine" -ForegroundColor Cyan
Write-Host "  tools -> $tools"
Write-Host "  data  -> $dataRoot"
if ($syncEnabled) { Write-Host "  sync  -> $repoRoot (git)" } else { Write-Host "  sync  -> off (local only)" }
Write-Host ""

$linkTools = Join-Path $claudeDir 'timesheet-tools'
$linkData  = Join-Path $claudeDir 'timesheet-data'
$linkSkill = Join-Path $claudeDir 'skills\timesheet'

if ($Plan) {
  Write-Host "PLAN (nothing will be changed)"
  if ($prevDataRoot -and (Test-Path $prevDataRoot) -and
      (Norm-Path $prevDataRoot) -ne (Norm-Path $dataRoot)) {
    Write-Host "  migrate  $prevDataRoot"
    Write-Host "        -> $dataRoot   (activity-log.md + raw\)"
  }
  Write-Host "  junction $linkTools -> $tools"
  Write-Host "  junction $linkData  -> $dataRoot"
  Write-Host "  junction $linkSkill -> $(Join-Path $tools 'skills\timesheet')"
  Write-Host "  config   $(Join-Path $claudeDir 'timesheet-config.json')"
  if (-not $NoHook) { Write-Host "  settings $(Join-Path $claudeDir 'settings.json')  (+ backup)" }
  if ($syncEnabled -and -not $NoTask) { Write-Host "  task     ClaudeTimesheetSync-$Machine (hourly)" }
  return
}

# ---- 1. seed the data folder ------------------------------------------------
Write-Host "[1/6] data folder"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot "raw\$Machine") | Out-Null

if ($prevDataRoot -and (Test-Path $prevDataRoot) -and
    (Norm-Path $prevDataRoot) -ne (Norm-Path $dataRoot)) {
  Move-TsData $prevDataRoot $dataRoot | Out-Null
}

$logFile = Join-Path $dataRoot 'activity-log.md'
if (-not (Test-Path $logFile)) {
  Copy-Item (Join-Path $tools 'templates\activity-log.md') $logFile
  Write-Host "  seeded activity-log.md" -ForegroundColor Green
} else {
  Write-Host "  ok     activity-log.md (kept your existing log)"
}
if ($syncEnabled) {
  $gi = Join-Path $repoRoot '.gitignore'
  if (-not (Test-Path $gi)) {
    Copy-Item (Join-Path $tools 'templates\data-repo.gitignore') $gi
    Write-Host "  seeded .gitignore in the data repo" -ForegroundColor Green
  }
  $rd = Join-Path $repoRoot 'README.md'
  if (-not (Test-Path $rd)) { Copy-Item (Join-Path $tools 'templates\data-repo-README.md') $rd }
  # Stage them so the first sync-push commit carries them; sync-push only adds
  # paths under dataRoot, so untracked repo-root files would never land.
  Invoke-Git -C $repoRoot add -- $gi $rd | Out-Null
}

# ---- 2. junctions -----------------------------------------------------------
Write-Host "`n[2/6] junctions"
New-JunctionSafe -Link $linkTools -Target $tools
New-JunctionSafe -Link $linkData  -Target $dataRoot
New-JunctionSafe -Link $linkSkill -Target (Join-Path $tools 'skills\timesheet')

# ---- 3. config (preserve what the user already customised) ------------------
Write-Host "`n[3/6] timesheet-config.json"
$cfgPath = Join-Path $claudeDir 'timesheet-config.json'
if (Test-Path $cfgPath) {
  $cfg = (Get-Content -Raw -Encoding UTF8 $cfgPath) | ConvertFrom-Json
  Copy-Item $cfgPath "$cfgPath.bak" -Force
  Write-Host "  backup -> timesheet-config.json.bak (your projects/git rules are kept)"
} else {
  $cfg = (Get-Content -Raw -Encoding UTF8 (Join-Path $tools 'config.example.json')) | ConvertFrom-Json
  # start clean: the example rules are illustrative, not real
  $cfg.projects = @()
  $cfg.git.hostMap = [PSCustomObject]@{}
  $cfg.git.searchRoots = @('~/Documents')
  Write-Host "  created from config.example.json - EDIT the 'projects' rules next" -ForegroundColor Yellow
}
function Set-Prop($obj, $name, $val) {
  if ($obj.PSObject.Properties[$name]) { $obj.$name = $val }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $val }
}
Set-Prop $cfg 'toolsRoot' $tools
Set-Prop $cfg 'dataRoot'  $dataRoot
Set-Prop $cfg 'machine'   $Machine
if (-not $cfg.sync) { Set-Prop $cfg 'sync' ([PSCustomObject]@{ enabled = $false; repoRoot = ''; autoPush = $true }) }
Set-Prop $cfg.sync 'enabled'  $syncEnabled
Set-Prop $cfg.sync 'repoRoot' $repoRoot
if (-not $cfg.git.authorPattern) {
  $email = @(Invoke-Git config user.email)[0]
  if ($email) { Set-Prop $cfg.git 'authorPattern' $email; Write-Host "  git author -> $email (from git config)" }
}
Write-Utf8NoBom $cfgPath (($cfg | ConvertTo-Json -Depth 20))
Write-Host "  saved $cfgPath"

# ---- 4. settings.json (hooks + statusLine), idempotent + backup -------------
Write-Host "`n[4/6] settings.json"
if ($NoHook) {
  Write-Host "  skipped (-NoHook) - see INSTRUCTION.md for the manual block"
} else {
  $settingsPath = Join-Path $claudeDir 'settings.json'
  if (Test-Path $settingsPath) {
    $settings = (Get-Content -Raw -Encoding UTF8 $settingsPath) | ConvertFrom-Json
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    Write-Host "  backup -> settings.json.bak"
  } else {
    $settings = [PSCustomObject]@{}
  }
  function Ensure-Prop($obj, $name, $val) {
    if (-not $obj.PSObject.Properties[$name]) { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $val }
  }
  Ensure-Prop $settings 'hooks' ([PSCustomObject]@{})
  Ensure-Prop $settings.hooks 'SessionStart' @()
  Ensure-Prop $settings.hooks 'SessionEnd' @()

  # A function that emits an empty array returns NOTHING to the pipeline, so
  # `$x = Filter-Something @()` lands $null on the property - and the next
  # `@($null) + $entry` then writes a literal null into the hook list. Every
  # helper below returns `,$out` (comma = keep the array intact) and drops nulls,
  # which also repairs a settings.json an older installer already corrupted.
  function Clean-Events($events) {
    $out = @(@($events) | Where-Object { $null -ne $_ })
    return ,$out
  }
  $settings.hooks.SessionStart = Clean-Events $settings.hooks.SessionStart
  $settings.hooks.SessionEnd   = Clean-Events $settings.hooks.SessionEnd

  # True only if a hook already points at the EXACT script path we want. Matching
  # on the bare filename would let a stale hook from an older install satisfy the
  # check, so the correct hook never gets added and the banner logs to a dead file.
  function Hook-AtPath($events, $scriptPath) {
    foreach ($grp in @($events)) {
      foreach ($h in @($grp.hooks)) {
        if ($h.command -and $h.command -like ('*"' + $scriptPath + '"*')) { return $true }
      }
    }
    return $false
  }
  # Drop any hook groups whose command references $leaf but not at $scriptPath.
  function Remove-StaleHook($events, $scriptPath) {
    $leaf = Split-Path -Leaf $scriptPath
    $out = @(@($events) | Where-Object {
      if ($null -eq $_) { return $false }
      $keep = $true
      foreach ($h in @($_.hooks)) {
        if ($h.command -and $h.command -like "*$leaf*" -and $h.command -notlike ('*"' + $scriptPath + '"*')) { $keep = $false }
      }
      $keep
    })
    return ,$out
  }
  function Cmd-Entry($scriptPath, $matcher, $timeout, $status) {
    $e = [PSCustomObject]@{ hooks = @([PSCustomObject]@{ type = 'command'; command = ('powershell -NoProfile -File "' + $scriptPath + '"'); timeout = $timeout; statusMessage = $status }) }
    if ($matcher) { $e | Add-Member -NotePropertyName matcher -NotePropertyValue $matcher -Force }
    return $e
  }

  $reminder = Join-Path $scripts 'session-reminder.ps1'
  $pull     = Join-Path $scripts 'sync-pull.ps1'
  $push     = Join-Path $scripts 'sync-push.ps1'

  foreach ($sp in @($reminder, $pull)) {
    $settings.hooks.SessionStart = Remove-StaleHook $settings.hooks.SessionStart $sp
  }
  $settings.hooks.SessionEnd = Remove-StaleHook $settings.hooks.SessionEnd $push

  if (-not (Hook-AtPath $settings.hooks.SessionStart $reminder)) {
    $settings.hooks.SessionStart = @($settings.hooks.SessionStart) + (Cmd-Entry $reminder 'startup|resume|clear' 15 'Loading timesheet secretary...')
    Write-Host "  + SessionStart session-reminder"
  }
  if ($syncEnabled) {
    if (-not (Hook-AtPath $settings.hooks.SessionStart $pull)) {
      $settings.hooks.SessionStart = @($settings.hooks.SessionStart) + (Cmd-Entry $pull 'startup|resume|clear' 30 'Syncing timesheet...')
      Write-Host "  + SessionStart sync-pull"
    }
    if (-not (Hook-AtPath $settings.hooks.SessionEnd $push)) {
      $settings.hooks.SessionEnd = @($settings.hooks.SessionEnd) + (Cmd-Entry $push $null 60 'Pushing activity...')
      Write-Host "  + SessionEnd sync-push"
    }
  }
  $slCmd = 'powershell -NoProfile -File "' + (Join-Path $scripts 'statusline-command.ps1') + '"'
  Ensure-Prop $settings 'statusLine' ([PSCustomObject]@{ type = 'command'; command = $slCmd })
  if ($settings.statusLine.command -notlike '*statusline-command.ps1*') {
    Write-Host "  ! you already have a custom statusLine - left it alone" -ForegroundColor Yellow
  } else {
    $settings.statusLine.command = $slCmd
  }
  Write-Utf8NoBom $settingsPath (($settings | ConvertTo-Json -Depth 20))
  Write-Host "  saved settings.json"
}

# ---- 5. hourly scheduled task (sync mode only) -----------------------------
Write-Host "`n[5/6] scheduled task"
$taskName = "ClaudeTimesheetSync-$Machine"
if (-not $syncEnabled) {
  Write-Host "  skipped (no data repo - nothing to push)"
} elseif ($NoTask) {
  Write-Host "  skipped (-NoTask)"
} else {
  $push    = Join-Path $scripts 'sync-push.ps1'
  $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
             -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $push + '" -Quiet')
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(5) `
             -RepetitionInterval (New-TimeSpan -Hours 1)
  # AllowStartIfOnBatteries/DontStopIfGoingOnBatteries: laptops are often on
  # battery - without these the hourly sync sits Queued and never runs.
  $set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
             -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
     -Settings $set -Description 'Hourly Claude timesheet activity sync' -Force | Out-Null
  Write-Host "  registered '$taskName' (hourly)" -ForegroundColor Green
}

# ---- 6. initial export ------------------------------------------------------
Write-Host "`n[6/6] initial export"
. "$scripts\tsconfig.ps1"
$pyInfo = Resolve-TsPython
if ($pyInfo) {
  $pre = $pyInfo.Pre
  & $pyInfo.Exe @pre (Join-Path $scripts 'export_activity.py') --machine $Machine
} else {
  Write-Host "  no real python found (only the Windows Store stub, if any)" -ForegroundColor Yellow
  Write-Host "  install Python 3 from python.org, then re-run: python scripts\export_activity.py"
}

Write-Host "`nDone." -ForegroundColor Cyan
Write-Host "Next:"
Write-Host "  1. edit $cfgPath -> add your 'projects' rules (see INSTRUCTION.md step 3)"
Write-Host "  2. start a NEW Claude Code session to pick up the skill + hooks"
Write-Host "  3. sanity check:  powershell -NoProfile -File `"$scripts\doctor.ps1`""
