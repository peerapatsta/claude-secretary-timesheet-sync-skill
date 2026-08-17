# INSTRUCTION — set up claude timesheet secretary on your machine

Everything you need to do, in order. Steps 1–4 are required; 5–7 are optional.

**Requirements:** Windows 10/11 · PowerShell 5.1+ (built in) · Python 3 on `PATH`
(from python.org — the Microsoft Store stub does **not** work) · Claude Code ·
git (only if you want the private data repo in step 5).

---

## Step 1 — Clone this repo

Put it anywhere permanent. The installer links to it in place, so **don't move
or delete it afterwards.**

```powershell
git clone https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill.git C:\tools\claude-secretary-timesheet-sync-skill
cd C:\tools\claude-secretary-timesheet-sync-skill
```

## Step 2 — Run the installer

Pick the mode you want. Start with local-only if you're not sure — you can
re-run the installer later with `-DataRepo` to upgrade to sync.

```powershell
# A) local only — log lives in <Documents>\claude-timesheet-data
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# B) log lives in YOUR OWN private git repo (see step 5 to create it first)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo "C:\src\my-timesheet-data"

# ...or let the installer clone that repo for you
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo "https://github.com/you/my-timesheet-data.git"
```

Dry run first if you want to see the plan: add `-Plan`.

What it does:

| # | Action |
|---|---|
| 1 | Seeds your data folder: `activity-log.md`, `raw\<MACHINE>\` |
| 2 | Junctions `~\.claude\timesheet-tools`, `~\.claude\timesheet-data`, `~\.claude\skills\timesheet` |
| 3 | Writes `~\.claude\timesheet-config.json` (an existing one is backed up and its settings kept) |
| 4 | Merges the SessionStart/SessionEnd hooks + `statusLine` into `~\.claude\settings.json` (backup first) |
| 5 | Registers the hourly `ClaudeTimesheetSync-<MACHINE>` task (sync mode only) |
| 6 | Runs a first activity export |

Other switches: `-DataDir <path>` (plain folder, no git) · `-Machine <name>` ·
`-NoTask` · `-NoHook` (leave `settings.json` alone — see step 7).

Because everything hangs off those junctions, **no path in the skill or the
scripts contains a username** — the same commands work on every machine.

## Step 3 — Map your repos to project names  ← the one edit that matters

Open `~\.claude\timesheet-config.json` and fill in `projects`. Each rule is a
case-insensitive **regex** matched against the full lowercased working
directory; **first match wins**. No match → the folder name is used.

```jsonc
"projects": [
  { "match": "acme-billing|billing-api",   "name": "BILLING" },
  { "match": "acme-web|storefront",        "name": "WEB" },
  { "match": "runbook|devops?",            "name": "DevOps" }
]
```

Also worth setting while you're in there:

| Key | What |
|---|---|
| `timezoneOffsetHours` | your UTC offset — hours are bucketed into days with it (Bangkok = 7) |
| `idleCapMinutes` | a gap longer than this counts as "away", not work (default 25) |
| `lastSubmitted` | the last timesheet date you already handed in; the banner offers to backfill days after it. `""` disables the offer |
| `git.authorPattern` | passed to `git log --author` when backfilling. Auto-filled from `git config user.email` |
| `git.searchRoots` | folders scanned for git repos during backfill |
| `git.hostMap` | remote host → project name, e.g. `"gitlab.acme.com": "BILLING"` |

Check what the tooling actually resolved:

```powershell
python "$env:USERPROFILE\.claude\timesheet-tools\scripts\tsconfig.py"
```

## Step 4 — Restart Claude Code and verify

Start a **new** session. You should see:

- an ASCII banner asking what you're working on, and
- a status line like `[BILLING?] | 12m03s | ctx 34k/200k 17% | 166k left`

The `?` means the project was **guessed** from the folder. Tell Claude the task;
it pins the project (`set-project.ps1`) and the `?` disappears.

If anything is off:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude\timesheet-tools\scripts\doctor.ps1"
```

`doctor.ps1` prints PASS/FAIL per component with the exact fix for each failure.

---

## Step 5 — (Optional) Your own private data repo

This is how you keep one log across several computers, and how you get a real
history of your hours instead of last-write-wins file sync.

**Keep it PRIVATE.** It holds your real hours, the repos and branches you worked
on, the files you edited and your commit subjects.

```powershell
# on github.com: New repository -> my-timesheet-data -> Private -> Create
git clone https://github.com/you/my-timesheet-data.git C:\src\my-timesheet-data
cd C:\tools\claude-secretary-timesheet-sync-skill
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo C:\src\my-timesheet-data
```

The installer seeds `.gitignore` + `README.md` in it and sets
`dataRoot = <repo>\timesheet`. From then on:

- **hourly Scheduled Task** → `sync-push.ps1`: `git pull --rebase --autostash`,
  export this machine's activity, commit, push
- **SessionStart** → `sync-pull.ps1`; **SessionEnd** → `sync-push.ps1`

To add a second machine: clone **both** repos there and run step 2B again. Each
machine writes only its own `raw/<MACHINE>/YYYY-MM.jsonl`, so git never has to
merge raw data. When backfilling, hours from *different* machines on the same
day are **additive** (you can't be on two at once); within one machine they're
best-of against git.

**What lands in git:** derived fields only — active minutes, project, repo,
branch, edited-file *names*, commit subjects, counts, session titles. Prompt and
response text is never written.

## Step 6 — (Optional) Daily use cheat-sheet

| You say | Claude does |
|---|---|
| answer the session-start prompt | opens an `In progress` row and pins the project |
| "done" / a PR merges | asks "Is it done?", confirms hours, marks `Done` |
| "what did I do this week?" | prints the table + per-day and range totals |
| "backfill since 2026-06-01" | reconstructs from git commits + Claude history, shows proposed rows, waits for your OK |
| "export the timesheet" | `activity-log.csv` / `.xlsx` next to the log |

Manual equivalents (`<T>` = `$env:USERPROFILE\.claude\timesheet-tools\scripts`):

```powershell
python "<T>\session-summary.py" --date 2026-08-17    # this machine, per session
python "<T>\session-summary.py" --latest 3
python "<T>\reconcile.py" --since 2026-08-01         # all machines (sync mode)
python "<T>\export_activity.py"                      # refresh raw for this machine
python "<T>\export_csv.py"                           # -> activity-log.csv
python "<T>\export_excel.py"                         # -> activity-log.xlsx (needs openpyxl)
powershell -File "<T>\set-project.ps1" BILLING       # pin the status-line project
powershell -File "<T>\set-project.ps1" -Clear        # back to the auto-guess
powershell -File "<T>\sync-push.ps1"                 # force a sync now
```

## Step 7 — (Optional) Wire the hooks by hand

Only needed if you installed with `-NoHook` or manage `settings.json` yourself.
Add to `~\.claude\settings.json`, replacing `<T>` with the real
`...\.claude\timesheet-tools\scripts` path (`sync-pull`/`sync-push` are for sync
mode only):

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File \"<T>\\statusline-command.ps1\""
  },
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear",
        "hooks": [{ "type": "command", "command": "powershell -NoProfile -File \"<T>\\session-reminder.ps1\"", "timeout": 15 }] },
      { "matcher": "startup|resume|clear",
        "hooks": [{ "type": "command", "command": "powershell -NoProfile -File \"<T>\\sync-pull.ps1\"", "timeout": 30 }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "powershell -NoProfile -File \"<T>\\sync-push.ps1\"", "timeout": 60 }] }
    ]
  }
}
```

---

## Updating

```powershell
cd C:\tools\claude-secretary-timesheet-sync-skill
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1   # idempotent
```

The junctions mean a `git pull` alone already updates the skill and the scripts;
re-running the installer just re-checks the hooks and the config schema. Your
`projects` rules and your log are never overwritten.

## Uninstalling

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes the junctions, the hooks, the statusLine and the scheduled task.
**Your log and data repo are never touched.** Add `-Purge` to also delete
`timesheet-config.json`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No banner at session start | Hook missing or pointing at an old path → `doctor.ps1`, then re-run `install.ps1` |
| Status line missing or `[no project]` | `statusLine` not set, or you're in a folder no rule matches → step 3 |
| Status line keeps the `?` | Nothing pinned yet — tell Claude the task, or run `set-project.ps1 <NAME>` |
| `Python was not found` | That's the Microsoft Store stub. Install Python 3 from python.org and tick "Add to PATH" |
| `no sessions in range` | No Claude Code transcripts under `~\.claude\projects` for those dates |
| `reconcile.py` sees one machine | Sync off, or the other machines haven't pushed → `git pull`, check `doctor.ps1` |
| Hourly sync never runs | Laptop on battery → the installer already sets `AllowStartIfOnBatteries`; re-run `install.ps1` if the task predates that |
| Hours look too high | Lower `idleCapMinutes`; long unattended runs count as active up to that cap |
| Wrong day for late-night work | `timezoneOffsetHours` doesn't match your locale |

Claude never writes a row without asking, and never invents hours — if a number
can't be grounded in a transcript or a commit, it asks you.
