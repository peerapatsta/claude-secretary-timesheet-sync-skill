<#
  Shared config loader for the PowerShell side of the timesheet tooling.
  Dot-source it:   . "$PSScriptRoot\tsconfig.ps1"

  Mirrors scripts/tsconfig.py so the status line, the hook and the python
  scripts all agree on dataRoot / project names without duplicating settings.

  Lookup order:  $env:CLAUDE_TIMESHEET_CONFIG  ->  ~\.claude\timesheet-config.json
                 ->  built-in defaults.
#>

function Get-TsConfigPath {
  if ($env:CLAUDE_TIMESHEET_CONFIG) { return $env:CLAUDE_TIMESHEET_CONFIG }
  return (Join-Path $env:USERPROFILE '.claude\timesheet-config.json')
}

function Get-TsConfig {
  $cfg = [PSCustomObject]@{
    version             = 1
    dataRoot            = ''
    toolsRoot           = ''
    machine             = ''
    timezoneOffsetHours = 7
    idleCapMinutes      = 25
    lastSubmitted       = ''
    sync                = [PSCustomObject]@{ enabled = $false; repoRoot = ''; autoPush = $true }
    projects            = @()
    git                 = [PSCustomObject]@{ authorPattern = ''; searchRoots = @(); hostMap = [PSCustomObject]@{} }
  }
  $path = Get-TsConfigPath
  if (Test-Path $path) {
    try {
      $user = (Get-Content -Raw -Encoding UTF8 $path) | ConvertFrom-Json
      foreach ($p in $user.PSObject.Properties) {
        if ($p.Name -like '_comment*') { continue }
        if ($cfg.PSObject.Properties[$p.Name]) { $cfg.($p.Name) = $p.Value }
        else { $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
      }
    } catch {
      Write-Host "[tsconfig] WARNING: could not read $path - $_"
    }
  }
  if (-not $cfg.dataRoot) {
    $cfg.dataRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'claude-timesheet'
  }
  if (-not $cfg.machine) { $cfg.machine = $env:COMPUTERNAME }
  return $cfg
}

function Get-TsDataRoot { (Get-TsConfig).dataRoot }

function Get-TsLogPath { Join-Path (Get-TsConfig).dataRoot 'activity-log.md' }

# Working directory -> short project name. Same rule order as tsconfig.py:
# config regexes first (first match wins), else the last path segment.
function Get-TsProjectName {
  param([string]$Path, $Config)
  if (-not $Config) { $Config = Get-TsConfig }
  if (-not $Path) { return 'no project' }
  $pl = $Path.Replace('\', '/').ToLower()
  foreach ($rule in @($Config.projects)) {
    if (-not $rule.match) { continue }
    try { if ($pl -match $rule.match) { return $rule.name } } catch {}
  }
  $seg = ($Path.TrimEnd('\', '/') -split '[\\/]')[-1]
  if ($seg) { return $seg }
  return 'no project'
}

# MD5 of the normalized cwd. set-project.ps1 (writer) and statusline-command.ps1
# (reader) both key on this, so they can never land on different files.
function Get-TsCwdKey {
  param([string]$Path)
  $norm  = $Path.ToLower().TrimEnd('\', '/')
  $md5   = [System.Security.Cryptography.MD5]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($norm)
  $hex   = ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
  return $hex.Substring(0, 12)
}

# Resolve a REAL python, skipping the Windows Store execution-alias stub under
# ...\WindowsApps\ (it only prints "Python was not found" and breaks exports).
# Returns @{ Exe = <path>; Pre = @(...) } or $null.
function Resolve-TsPython {
  foreach ($name in 'python', 'python3') {
    foreach ($c in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
      if ($c.Source -and $c.Source -notlike '*\WindowsApps\*') { return @{ Exe = $c.Source; Pre = @() } }
    }
  }
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py -and $py.Source -notlike '*\WindowsApps\*') { return @{ Exe = $py.Source; Pre = @('-3') } }
  return $null
}
