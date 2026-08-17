<#
  Pull the latest timesheet state from YOUR data repo before work starts.
  Wired into the Claude Code SessionStart hook. Safe + non-interactive: rebases
  local commits on top of remote and autostashes any dirty edits so it never
  blocks. Never fails the session - always exits 0.

  No-ops when sync.enabled is false.
#>
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\tsconfig.ps1"

$cfg = Get-TsConfig
if (-not $cfg.sync.enabled) { exit 0 }

$repo = $cfg.sync.repoRoot
if (-not $repo -or -not (Test-Path (Join-Path $repo '.git'))) {
  Write-Host "sync-pull: sync.repoRoot is not a git repo: $repo"
  exit 0
}

try {
  # SilentlyContinue: Windows PowerShell wraps a native command's redirected
  # stderr in NativeCommandError records - noise, not failure.
  $ErrorActionPreference = 'SilentlyContinue'
  & git -C $repo pull --rebase --autostash --no-edit 2>&1 |
    ForEach-Object { Write-Host $_.ToString() }
} catch {
  Write-Host "sync-pull: $_"
}
exit 0
