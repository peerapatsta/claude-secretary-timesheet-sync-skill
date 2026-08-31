<#
  Collect THIS machine's activity and publish it to YOUR data repo.

  Runs from: the hourly Scheduled Task (primary), the SessionEnd hook, and
  manually. Idempotent and non-interactive - safe to fire as often as you like.

  Steps: pull --rebase --autostash  ->  export_activity.py (this machine's raw)
         ->  add <dataRoot>  ->  commit if changed  ->  push.

  Both raw/ AND the curated activity-log.md are auto-committed. The log is
  included on purpose: it is the thing you actually submit, and if the machine
  that wrote a row never commits it, the row never reaches any other machine.
  pull --rebase --autostash, plus the fact that only one machine is edited per
  day, keeps the "clobber a mid-edit row" risk theoretical.

  No-ops (exit 0) when sync.enabled is false. Logs to <dataRoot>\sync.log.
#>
param([switch]$Quiet)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\tsconfig.ps1"

$cfg      = Get-TsConfig
$dataRoot = $cfg.dataRoot
$machine  = $cfg.machine
$log      = Join-Path $dataRoot 'sync.log'

function Log($m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  if (Test-Path $dataRoot) { Add-Content -Path $log -Value $line -Encoding utf8 }
  if (-not $Quiet) { Write-Host $line }
}

if (-not $cfg.sync.enabled) { if (-not $Quiet) { Write-Host "sync disabled - nothing to push" }; exit 0 }
$repo = $cfg.sync.repoRoot
if (-not $repo -or -not (Test-Path (Join-Path $repo '.git'))) {
  Log "ERROR: sync.repoRoot is not a git repo: $repo"
  exit 0
}

$pyInfo = Resolve-TsPython

# Windows PowerShell turns a native command's redirected stderr into ErrorRecords
# (NativeCommandError) and flips $? even on exit 0, which floods the log with
# bogus stack traces. Silence the record, keep the text.
# No param block on purpose: $args swallows -C/-- verbatim instead of PowerShell
# trying to bind them as parameters of this function.
function Invoke-Git {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  $out = & git @args 2>&1 | ForEach-Object { $_.ToString() }
  $ErrorActionPreference = $prev
  return $out
}

try {
  Invoke-Git -C $repo pull --rebase --autostash --no-edit |
    ForEach-Object { if ($_.Trim()) { Log "pull: $($_.Trim())" } }

  if ($pyInfo) {
    $pre = $pyInfo.Pre
    & $pyInfo.Exe @pre (Join-Path $PSScriptRoot 'export_activity.py') --machine $machine 2>&1 |
      Out-String | ForEach-Object { if ($_.Trim()) { Log "export: $($_.Trim())" } }
  } else {
    Log "export: SKIPPED (no real python found - only the Windows Store stub, if any)"
  }

  # sync.extraPaths: repo-relative paths committed alongside dataRoot. Lets one
  # repo carry more than the timesheet (e.g. a junctioned Claude memory folder)
  # without a second scheduled task racing this one on the same working tree.
  $targets = @($dataRoot)
  foreach ($rel in @($cfg.sync.extraPaths)) {
    if (-not $rel) { continue }
    $abs = Join-Path $repo $rel
    if (Test-Path $abs) { $targets += $abs } else { Log "extraPath missing, skipped: $abs" }
  }

  Invoke-Git -C $repo add -- @targets | Out-Null
  $dirty = Invoke-Git -C $repo status --porcelain -- @targets
  # Also pick up anything install.ps1 staged at the repo root (.gitignore, README).
  $staged = Invoke-Git -C $repo diff --cached --name-only
  if ($dirty -or $staged) {
    $today = Get-Date -Format 'yyyy-MM-dd'
    Invoke-Git -C $repo commit -m "timesheet: $machine $today auto-sync" | Out-Null
    if ($cfg.sync.autoPush) {
      Invoke-Git -C $repo push | ForEach-Object { if ($_.Trim()) { Log "push: $($_.Trim())" } }
      Log "committed + pushed ($machine)"
    } else {
      Log "committed, push skipped (sync.autoPush = false)"
    }
  } else {
    Log "nothing to sync"
  }
} catch {
  Log "ERROR: $_"
}
exit 0
