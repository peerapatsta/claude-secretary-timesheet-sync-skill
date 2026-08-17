<#
  Pin the current project for the status line (timesheet flow, step S).

  Writes  ~\.claude\session-projects\proj-<cwdKey>.txt  where cwdKey is an MD5 of
  the current working directory. statusline-command.ps1 reads the same key, so the
  write and the read can never land on different files (no session-id guessing).
  Deterministic + machine-independent.

  Usage (Claude runs this from the project working dir, no cd first):
      powershell -NoProfile -File "<tools>\scripts\set-project.ps1" BILLING
  Optional explicit dir:
      powershell -NoProfile -File "<tools>\scripts\set-project.ps1" BILLING -Cwd "C:\path"
  Clear the pin (fall back to the auto-guess):
      powershell -NoProfile -File "<tools>\scripts\set-project.ps1" -Clear
#>
param(
  [Parameter(Position = 0)][string]$Name,
  [string]$Cwd,
  [switch]$Clear
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\tsconfig.ps1"

if (-not $Clear -and -not $Name) { throw "give a project name, or use -Clear" }
if (-not $Cwd) { $Cwd = (Get-Location).Path }

$dir = Join-Path $env:USERPROFILE '.claude\session-projects'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$key  = Get-TsCwdKey $Cwd
$file = Join-Path $dir "proj-$key.txt"

if ($Clear) {
  if (Test-Path $file) { Remove-Item $file -Force }
  Write-Host "cleared pinned project for $Cwd"
  return
}

$Name.Trim() | Set-Content -Path $file -Encoding utf8
Write-Host "pinned project '$Name' for $Cwd"
Write-Host "  -> $file"
