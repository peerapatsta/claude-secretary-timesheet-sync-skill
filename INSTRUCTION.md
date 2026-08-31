# How to use it

A guided tour: what it does, how to set it up, and what a normal day looks like.
Skip to [Setup](#setup) if you just want it running.

- [What it does for you](#what-it-does-for-you)
- [Which mode?](#which-mode)
- [Setup](#setup)
- [A normal day](#a-normal-day)
- [Command reference](#command-reference)
- [Settings](#settings)
- [Mode 2 — multi-sync in detail](#mode-2--multi-sync-in-detail)
- [Updating, moving, uninstalling](#updating-moving-uninstalling)
- [Troubleshooting](#troubleshooting)
- [Appendix — wiring the hooks by hand](#appendix--wiring-the-hooks-by-hand)

---

## What it does for you

Think of it as a secretary sitting next to you who writes down what you did.
You talk to Claude normally; it keeps the log.

### 1. It asks, so you never lose a day

Every new Claude Code session opens with this:

```
====================================================
   TIMESHEET LOG  -  2026-08-17
====================================================
   >> What are you working on RIGHT NOW, and on which PROJECT?
      (my guess is [NAME?] in the status line below)
   >> Tell me the task and I'll pin the project - the '?' drops off.
   !! Nothing is logged until you say - don't leave today blank.
====================================================
```

Answer it once and a row opens as `In progress`. Switch to something else and it
asks whether the previous task is finished before starting the new one.

### 2. It shows the project in the status line

```
[BILLING?] | 12m03s | ctx 34k/200k 17% | 166k left
 ▲          ▲        ▲
 │          │        └─ context used, coloured green → yellow → red
 │          └─ how long this session has been open
 └─ the project — "?" means guessed from the folder, not confirmed yet
```

Tell Claude the task and the `?` disappears: `[BILLING]`. The guess comes from
regex rules you set once (see [Settings](#settings)).

### 3. It measures your hours instead of guessing

This is the part a human can't do from memory. It reads the real session
transcript and counts the time between messages, ignoring any gap longer than
your idle cap (default 25 min) so lunch and meetings don't get billed.

```
SESSION b361917c  2026-08-17  BILLING  [feat/invoice-rounding]
  hours : 3.21h active  (09:12-14:40, 288 msgs, idle-cap 25m)
  title : Fix rounding on invoice line totals
  edited: 7 file(s): invoice.service.ts, invoice.spec.ts, money.ts, ...
  ran   : 24 command(s)
```

Worked on three projects today? It splits the hours per project and per git
branch, so you get three correct rows instead of one vague one.

### 4. It rebuilds days you forgot to log

Just say **"backfill since June 1"**. It reads two independent sources:

| Source | Tells you |
|---|---|
| **git commits** | what actually landed |
| **Claude activity** | where the time went — including debugging with no commit |

Then it reconciles them: hours are the **best of the two, never the sum** (same
work, measured two ways). If Claude time ≫ commits, the extra was
debugging/research — it counts it and tags the row `debug`. A day with activity
but no commit is still a work day. A day with neither gets flagged as
meeting/leave for you to confirm. Commit-derived numbers are marked `est.`

You get proposed rows to approve. **Nothing is written until you say yes.**

### 5. It answers questions about your log

> "what did I do this week?"

You get the table plus per-day and range totals, with empty days and stale
`In progress` rows flagged.

### 6. It hands you a spreadsheet

`.csv` for anything, or a formatted `.xlsx` with coloured status cells, a TOTAL
row, a frozen header and an autofilter — ready to attach to an email.

### What it can't see

git and Claude activity both miss **meetings, manual testing, whiteboard time,
and work done in your IDE without Claude**. The skill knows this and will ask
what isn't captured. It never invents a number to fill a blank.

---

## Which mode?

|  | 🖥️ **Mode 1 — Solo (offline)** | 🔄 **Mode 2 — Multi-sync** |
|---|---|---|
| Where the log lives | `<Documents>\claude-timesheet-data\` | `<your private repo>\timesheet\` |
| Needs git / an account | No | Yes — a **private** repo you own |
| Everything in *What it does* | ✅ | ✅ |
| One log across several computers | ❌ | ✅ |
| Hours added up per machine (`reconcile.py`) | ❌ | ✅ |
| Auto pull on session start / push hourly | ❌ | ✅ |
| Version history of your hours | ❌ | ✅ |

**Not sure? Pick Mode 1.** When a second computer shows up, re-run the installer
with `-DataRepo` — it *moves* your log and activity into the repo for you.

---

## Setup

**You need:** Windows 10/11 · PowerShell 5.1+ (built in) · **Python 3 from
python.org** (the Microsoft Store stub does *not* work) · Claude Code ·
git (Mode 2 only).

### Step 1 — Clone this repo

Put it somewhere permanent — the installer links to it in place, so don't move
or delete the folder afterwards.

```powershell
git clone https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill.git C:\tools\claude-secretary-timesheet-sync-skill
cd C:\tools\claude-secretary-timesheet-sync-skill
```

### Step 2 — Run the installer

**Mode 1 — Solo:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

**Mode 2 — Multi-sync.** Create a repo on GitHub first
(*New repository → **Private** → Create*), then:

```powershell
# let the installer clone it for you...
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo "https://github.com/you/my-timesheet-data.git"

# ...or point at a clone you already have
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo "C:\src\my-timesheet-data"
```

Want to see what it will touch first? Add `-Plan` — it prints the plan and
changes nothing.

<details>
<summary>What the installer actually does (6 steps)</summary>

| # | Action |
|---|---|
| 1 | Seeds your data folder: `activity-log.md`, `raw\<MACHINE>\`. If a previous install used a different location, **moves** the existing log + `raw\` across |
| 2 | Creates junctions: `~\.claude\timesheet-tools`, `~\.claude\timesheet-data`, `~\.claude\skills\timesheet` |
| 3 | Writes `~\.claude\timesheet-config.json` — an existing one is backed up and **your settings are kept** |
| 4 | Merges the hooks + `statusLine` into `~\.claude\settings.json` (backup first; your other hooks are left alone) |
| 5 | Mode 2 only: registers the hourly `ClaudeTimesheetSync-<MACHINE>` task, run hidden via a generated `.vbs` so no console window ever flashes |
| 6 | Runs a first activity export |

It is safe to re-run any time. A real folder it would replace with a junction is
renamed `*.pre-timesheet.bak` — never deleted.

Other switches: `-DataDir <path>` (plain folder somewhere else, no git) ·
`-Machine <name>` · `-NoTask` · `-NoHook` (leave `settings.json` alone —
see the [appendix](#appendix--wiring-the-hooks-by-hand)).

Because everything hangs off those junctions, **no path in the skill or the
scripts contains a username** — the same commands work on every machine.

</details>

### Step 3 — Tell it your project names ← the one edit that matters

Open `~\.claude\timesheet-config.json` and fill in `projects`. Each rule is a
case-insensitive **regex** matched against your working directory;
**first match wins**. No match → the folder name is used.

```jsonc
"projects": [
  { "match": "acme-billing|billing-api", "name": "BILLING" },
  { "match": "acme-web|storefront",      "name": "WEB" },
  { "match": "runbook|devops?",          "name": "DevOps" }
]
```

Now `C:\src\acme-billing-api` shows as `[BILLING?]` instead of
`[acme-billing-api?]`, and your rows say `BILLING`.

See [Settings](#settings) for the rest.

### Step 4 — Restart Claude Code and check

Start a **new** session. You should see the banner and a status line. Then:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude\timesheet-tools\scripts\doctor.ps1"
```

`doctor.ps1` prints PASS/FAIL for every component with the exact fix for each
failure, then shows your resolved settings and what project the current folder
maps to.

---

## A normal day

**09:10 — you open Claude Code in `C:\src\acme-billing-api`**

Banner appears. Status line says `[BILLING?]`.

> **You:** working on the invoice rounding bug
> **Claude:** Working on BILLING — opening a row for "invoice rounding bug".

Status line becomes `[BILLING]`. A row opens as `In progress`.

**12:30 — the fix lands**

> **You:** that's fixed, PR is up
> **Claude:** Is it done? I have ~3.2h active on this session — sound right?
> **You:** yes
> **Claude:** Marked Done, 3.25h, note "PR #412".

**13:40 — you switch projects**

> **You:** now looking at the checkout e2e flake in the web repo
> **Claude:** Did you finish the invoice work? … opening a WEB row.

**18:00 — wrapping up**

> **You:** done for today
> **Claude:** ~1.5h on WEB. The e2e is still failing — `Blocked` or `In progress`?

**Friday — the timesheet is due**

> **You:** what did I do this week?

Table + per-day and range totals.

> **You:** export it

`activity-log.xlsx`, ready to attach.

**And when you forgot to log Tuesday and Wednesday:**

> **You:** backfill since Monday

It reads commits + Claude activity, reconciles, and shows proposed rows. You
correct anything wrong, say yes, and it writes them.

---

## Command reference

You rarely need these — just talk to Claude. They're here for when you want to
run something yourself.

`<T>` = `$env:USERPROFILE\.claude\timesheet-tools\scripts`

```powershell
# hours on this machine
python "<T>\session-summary.py"                      # latest session
python "<T>\session-summary.py" --latest 3
python "<T>\session-summary.py" --date 2026-08-17
python "<T>\session-summary.py" --since 2026-08-01 --until 2026-08-31

# hours across ALL your machines (Mode 2)
python "<T>\reconcile.py" --since 2026-08-01         # git pull first
python "<T>\reconcile.py" --date 2026-08-17

# refresh this machine's raw activity
python "<T>\export_activity.py"

# hand-in formats
python "<T>\export_csv.py"                           # -> activity-log.csv
python "<T>\export_excel.py"                         # -> activity-log.xlsx (pip install openpyxl)

# status-line project
powershell -File "<T>\set-project.ps1" BILLING       # pin
powershell -File "<T>\set-project.ps1" -Clear        # back to the auto-guess

# maintenance
powershell -File "<T>\doctor.ps1"                    # health check
powershell -File "<T>\sync-push.ps1"                 # force a sync now (Mode 2)
python     "<T>\tsconfig.py"                         # show resolved settings
```

---

## Settings

Everything lives in `~\.claude\timesheet-config.json`. `config.example.json` in
this repo documents every key.

| Key | What it's for |
|---|---|
| `projects` | folder → short project name (see [step 3](#step-3--tell-it-your-project-names--the-one-edit-that-matters)) |
| `timezoneOffsetHours` | your UTC offset — decides which day late-night work belongs to (Bangkok = 7) |
| `idleCapMinutes` | a gap longer than this counts as "away", not work (default 25) |
| `lastSubmitted` | the last timesheet date you already handed in — the banner then offers to backfill days after it. `""` turns the offer off |
| `git.authorPattern` | passed to `git log --author` when backfilling. Auto-filled from `git config user.email` |
| `git.searchRoots` | folders scanned for git repos during backfill |
| `git.hostMap` | remote host → project name, e.g. `"gitlab.acme.com": "BILLING"` |
| `update` | daily check for a newer version of these tools; the banner tells you when one is out. `"enabled": false` never touches the network |
| `sync.extraPaths` | repo-relative paths committed *alongside* the timesheet, e.g. `["memory"]`. For when the data repo carries more than hours and you don't want a second scheduled task fighting this one over the same working tree. Empty by default |
| `dataRoot` · `machine` · `sync.enabled` · `sync.repoRoot` | written by the installer — change these by re-running it, not by hand |

Check what the tooling actually resolved at any time:

```powershell
python "$env:USERPROFILE\.claude\timesheet-tools\scripts\tsconfig.py"
```

---

## Mode 2 — multi-sync in detail

**Keep the data repo PRIVATE.** It holds your real hours, the repos and branches
you worked on, the files you edited and your commit subjects.

Once installed with `-DataRepo`:

- **hourly Scheduled Task** → `sync-push.ps1`: `git pull --rebase --autostash`,
  export this machine's activity, commit, push. The task calls `wscript.exe` with
  a generated one-line `.vbs`, not `powershell.exe` — Task Scheduler allocates a
  console before PowerShell can read `-WindowStyle Hidden`, so calling it directly
  flashes a black window every hour
- **SessionStart** → `sync-pull.ps1` · **SessionEnd** → `sync-push.ps1`

### Adding a second computer

Clone **both** repos there and run the installer again:

```powershell
git clone https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill.git C:\tools\claude-secretary-timesheet-sync-skill
cd C:\tools\claude-secretary-timesheet-sync-skill
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo "https://github.com/you/my-timesheet-data.git"
```

### Why it never conflicts

Each machine writes only its own `raw/<MACHINE>/YYYY-MM.jsonl`, so git never has
to merge activity data. When you backfill:

- hours from **the same machine** are best-of against git commits
- hours from **different machines on the same day are added together** — you
  can't be sitting at two computers at once

### What lands in git

Derived fields only: active minutes, project, repo, branch, edited-file *names*,
commit subjects, counts, Claude's session titles. **Prompt and response text is
never written.**

---

## Updating, moving, uninstalling

### Update

```powershell
cd C:\tools\claude-secretary-timesheet-sync-skill
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1   # idempotent
```

The junctions mean `git pull` alone already updates the skill and the scripts;
re-running the installer just re-checks the hooks and the config schema. Your
`projects` rules and your log are never overwritten.

You don't have to remember to check. Once a day the session banner tells you
when the upstream branch has a commit this clone doesn't:

```
   ** UPDATE AVAILABLE: timesheet tools - main is at a1b2c3d upstream (just checked).
      Run: git -C "C:\tools\claude-secretary-timesheet-sync-skill" pull --ff-only ...
```

The check is time-boxed and fails silent, so being offline or behind a dead VPN
costs you nothing at session start. Tune it with the `update` block in
`timesheet-config.json`, or run it yourself:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude\timesheet-tools\scripts\check-update.ps1" -Force
```

### Move your log (including Mode 1 → Mode 2)

Re-run the installer pointing at the new place — `activity-log.md` and `raw\`
follow automatically:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo C:\src\my-timesheet-data
```

The one case it won't handle is when **both** locations already hold an
`activity-log.md`. It leaves both alone and asks you to merge the rows yourself,
because there's no safe way to guess which rows win.

### Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Removes the junctions, the hooks, the statusLine and the scheduled task.
**Your log and data repo are never touched.** Add `-Purge` to also delete
`timesheet-config.json`.

---

## Troubleshooting

Run `doctor.ps1` first — it names the broken component and the fix.

| Symptom | Cause / fix |
|---|---|
| No banner at session start | Hook missing or pointing at an old path → `doctor.ps1`, then re-run `install.ps1` |
| Status line missing, or `[no project]` | `statusLine` not set, or you're in a folder no rule matches → [step 3](#step-3--tell-it-your-project-names--the-one-edit-that-matters) |
| Status line keeps the `?` | Nothing pinned yet — tell Claude the task, or run `set-project.ps1 <NAME>` |
| `Python was not found` | That's the Microsoft Store stub. Install Python 3 from python.org and tick "Add to PATH" |
| `no sessions in range` | No Claude Code transcripts under `~\.claude\projects` for those dates |
| `reconcile.py` only sees one machine | Mode 1, or the other machines haven't pushed → `git pull`, then `doctor.ps1` |
| Log looks empty after switching to a repo | The installer printed `NOT merged automatically` — your rows are still at the old `dataRoot`; merge them in by hand |
| A black console window flashes every hour | Your task predates the `wscript.exe` launcher — re-run `install.ps1`, then `doctor.ps1` should show `PASS task hidden`. A flash at **boot/logon only** is a different task: Windows' own `\Microsoft\Windows\Hotpatch\Monitoring` (disable it from an admin shell if it bothers you) |
| Hourly sync never runs | Laptop on battery → the installer sets `AllowStartIfOnBatteries`; re-run `install.ps1` if your task predates that |
| Hours look too high | Lower `idleCapMinutes` — long unattended runs count as active up to that cap |
| Work lands on the wrong day | `timezoneOffsetHours` doesn't match where you are |

---

## Appendix — wiring the hooks by hand

Only needed if you installed with `-NoHook` or manage `settings.json` yourself.
Replace `<T>` with your real `...\.claude\timesheet-tools\scripts` path.
`sync-pull` / `sync-push` are **Mode 2 only** — leave them out in Mode 1.

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
