# Claude Code status line
# Output: [Project] | <session time> | ctx <used>/<max> <pct> | <left> left
#
# Project resolution (deterministic, machine-independent):
#   1. override file  session-projects\proj-<cwdKey>.txt  -> pinned  -> "[NAME]"
#   2. else config `projects` regexes / folder name       -> guess   -> "[NAME?]"
#   3. else                                               ->         -> "[no project]"
# cwdKey is an MD5 of the normalized cwd, so the writer (set-project.ps1) and this
# reader always agree regardless of session id or machine.
$ErrorActionPreference = 'SilentlyContinue'
. "$PSScriptRoot\tsconfig.ps1"

$raw  = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { "[status line: bad input]"; return }

# ---- helpers ----
function Fmt([double]$n) {
    if ($n -ge 1000000) { return ("{0:0.0}M" -f ($n / 1000000)) }
    elseif ($n -ge 1000) { return ("{0:0}k"  -f ($n / 1000)) }
    else { return ("{0:0}" -f $n) }
}
$ESC = [char]27
function Color([string]$text, [string]$code) { "$ESC[${code}m$text$ESC[0m" }

# ---- 1. Project (config-derived guess; override file wins) ----
$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = $data.cwd }
if (-not $cwd) { $cwd = (Get-Location).Path }

$cfg      = Get-TsConfig
$key      = Get-TsCwdKey $cwd
$projFile = Join-Path $env:USERPROFILE ".claude\session-projects\proj-$key.txt"
if (Test-Path $projFile) {
    $project = (Get-Content $projFile -Raw).Trim()
    if (-not $project) { $project = Get-TsProjectName $cwd $cfg; $pinned = $false } else { $pinned = $true }
} else {
    $project = Get-TsProjectName $cwd $cfg
    $pinned  = $false
}

# ---- 2. Session time (wall clock) ----
$ms = 0.0
if ($data.cost -and $data.cost.total_duration_ms) { $ms = [double]$data.cost.total_duration_ms }
$ts = [TimeSpan]::FromMilliseconds($ms)
if     ($ts.TotalHours   -ge 1) { $time = "{0}h{1:D2}m" -f [int]$ts.TotalHours,   $ts.Minutes }
elseif ($ts.TotalMinutes -ge 1) { $time = "{0}m{1:D2}s" -f [int]$ts.TotalMinutes, $ts.Seconds }
else                            { $time = "{0}s"        -f [int]$ts.TotalSeconds }

# ---- 3 & 4. Context tokens (parse transcript tail for latest usage) ----
$max  = 200000
$used = 0
$tp = $data.transcript_path
if ($tp -and (Test-Path $tp)) {
    $tail = Get-Content $tp -Tail 120
    for ($i = $tail.Count - 1; $i -ge 0; $i--) {
        if ($tail[$i] -notmatch '"usage"') { continue }
        try {
            $u = ($tail[$i] | ConvertFrom-Json).message.usage
            if ($u -and ($null -ne $u.input_tokens)) {
                $used = [int]$u.input_tokens + [int]$u.cache_creation_input_tokens + [int]$u.cache_read_input_tokens
                break
            }
        } catch {}
    }
}
$left = $max - $used
if ($left -lt 0) { $left = 0 }
$pct = [int]([math]::Round(($used / $max) * 100))

# color the context block by how full it is
if     ($pct -ge 80) { $cc = "31" }   # red
elseif ($pct -ge 50) { $cc = "33" }   # yellow
else                 { $cc = "32" }   # green
$ctx     = Color ("ctx {0}/{1} {2}%" -f (Fmt $used), (Fmt $max), $pct) $cc
$leftStr = Color ("{0} left" -f (Fmt $left)) $cc

# pinned = solid cyan [NAME]; guessed = dim cyan [NAME?] (nudge to confirm)
if ($pinned) {
    $proj = Color ("[{0}]" -f $project) "36"
} elseif ($project -ne 'no project') {
    $proj = Color ("[{0}?]" -f $project) "2;36"
} else {
    $proj = Color "[no project]" "2;36"
}

"$proj | $time | $ctx | $leftStr"
