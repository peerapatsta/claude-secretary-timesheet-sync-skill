---
name: timesheet
description: >
  Your timekeeping secretary. Logs daily work as a timesheet (project, task,
  hours, status) and reconstructs missing days from git + Claude Code history.
  Use on any mention of timesheet, activity log, work breakdown, man-hours,
  "what did I do", backfill/reconstruct my hours, or starting/finishing a task.
  Also drives the session-start "which project/task?" prompt.
  Log file: ~\.claude\timesheet-data\activity-log.md
---

# Timesheet Secretary

Keep an accurate per-day record of the user's work so they can fill their
company timesheet without reconstructing from memory. Two modes: **live
tracking** (the normal session flow) and **reconstruct** (backfill days they
didn't log with you).

## Paths — stable on every machine, no hardcoded username

`install.ps1` creates two junctions so every path below is identical on every
machine and for every user:

| Shorthand | Path | What |
|---|---|---|
| `<TOOLS>` | `~\.claude\timesheet-tools` | this repo (scripts live in `<TOOLS>\scripts\`) |
| `<TS>` | `~\.claude\timesheet-data` | the user's own log + `raw/` activity |

Never write `C:\Users\<name>\...` into a command. Build the literal path from
the OS instead:

- **PowerShell:** `"$env:USERPROFILE\.claude\timesheet-tools\scripts\<script>"`
- **Git-Bash / Bash tool:** `"$HOME/.claude/timesheet-tools/scripts/<script>"`

Settings the user controls (project names, timezone, git author, sync) live in
`~\.claude\timesheet-config.json`. To see everything resolved:
`python "$HOME/.claude/timesheet-tools/scripts/tsconfig.py"`.

## The log

One file, one row per task under the current month's section (create if missing):
`<TS>\activity-log.md`

`| Date | Project | Task | Hours | Status | Notes |`
- Date `YYYY-MM-DD`; Project short name (the config's `projects` names); Task one line.
- Hours: real time, decimal to 0.25. **No daily total enforced** — never pad to 8h.
- Status: `Done` / `In progress` / `Blocked`. Notes: blockers, `est.`, `debug`, PR.

## Mode 1 — Live tracking

1. **Session start** (the SessionStart hook injects a reminder): on the **first
   user turn**, the status line already shows an auto-guessed project with a `?`
   (e.g. `[BILLING?]`) derived from the working dir. **Confirm it** — "Working on
   BILLING — what's the task?" — rather than asking blind; skip if already stated.
   Open an `In progress` row, then **pin the project** (step S) to clear the `?`.
   (Claude cannot speak before the user's first message — that's a Claude Code
   limitation — so the status line `?` is the pre-first-turn cue.)
2. **Switch** to another task/project → ask "Did you finish <task>?", close it, open new.
   Re-run step S with the new project's short name.

**Step S — pin the project for the status line.** The status line auto-guesses
the project from the working directory and shows it with a `?`. Pinning removes
the `?` and locks in the real name. Whenever the project is set or switched, run
— from the project working dir, do **not** `cd` first:

```powershell
powershell -NoProfile -File "$env:USERPROFILE\.claude\timesheet-tools\scripts\set-project.ps1" BILLING  # <- real short name
```

This keys the pin by a hash of the cwd (writer and status line agree by
construction — no session-id guessing, works the same on every machine). If the
auto-guess is already correct you may skip pinning, but pinning is what turns the
`?` off, so prefer to pin once the project is confirmed. If the guess is wrong
*often* for a repo, suggest adding a `projects` rule to the config.

3. **Looks done** (user says so / build·test·PR passes / they move on) → ask
   **"Is it done?"** Then set `Done` and fill Hours = your estimate from session
   wall-clock, **stated for confirmation** ("about how long? I have ~Xh"). Subtract
   idle/breaks. Never silently invent hours. For the hours + a truthful bullet
   summary, follow **Mode 3 — Session wrap** (ground the number with the script).

## Mode 2 — Reconstruct / backfill

When days are unlogged, offer once, then rebuild from two sources and reconcile.

**A. Git commits** (what landed). Read `git.authorPattern`, `git.searchRoots` and
`git.hostMap` from `~\.claude\timesheet-config.json` and substitute them below.
If `authorPattern` is empty, fall back to `git config user.email`.

```bash
for base in <searchRoots>; do
  [ -d "$base" ] && find "$base" -maxdepth 4 -type d -name ".git" 2>/dev/null
done | sort -u | while read g; do
  r=$(dirname "$g"); url=$(git -C "$r" remote get-url origin 2>/dev/null)
  host=$(echo "$url" | sed -E 's#https?://([^/]+)/.*#\1#')
  git -C "$r" log --all --no-merges --since=<START>T00:00:00 --until=<END>T00:00:00 \
      --author='<authorPattern>' --date=short --pretty=format:"%ad|$host|$(basename "$r")|%s"
  echo
done | grep -v '^$' | sort
```

Map each `host` through `git.hostMap` to a project short name. Group by day,
collapse into 1–3 task rows per day per project.

**B. Claude Code active time** (what hours, incl. uncommitted debugging).
Prefer the **per-session** transcript reader — it splits multi-project days
correctly and gives you real files-touched + session titles as bullet material:

```bash
python3 "$HOME/.claude/timesheet-tools/scripts/session-summary.py" --date 2026-07-30
#   ... or --since 2026-07-01 --until 2026-07-31   |   --latest 5   |   --all
```

Per session it prints precise active hours (inter-message gaps, idle-capped),
project + git branch, aiTitle, files edited, commands run, first prompt, then a
`hours by day + project` subtotal. Turn the scaffolding into truthful one-line
task rows — don't paste it verbatim.

**B (cross-machine).** `session-summary.py` reads only THIS machine. If sync is
enabled, use `reconcile.py`, which merges every machine's committed
`raw/<machine>/*.jsonl` exports (written by `export_activity.py`, run hourly per
machine):

```bash
python3 "$HOME/.claude/timesheet-tools/scripts/reconcile.py" --since 2026-07-01 --until 2026-07-31   # or --date
```

Same-machine hours are best-of vs git; **different machines on the same day are
additive** (you can't be on two at once). It prints proposed rows + bullet
material — confirm before writing. First `git pull` so you have the latest raw.

**Reconcile:** Hours = **best of A vs. B** — they're the same work measured two
ways, so do NOT add them. When B ≫ A, the extra is debugging/research: count it,
tag `debug`. A day with Claude activity but no commit is still a **work day**.
Mark commit-derived numbers `est.`; flag days with neither commits nor activity
as meeting/leave to confirm. Both sources miss meetings, manual testing, and
non-Claude IDE work — always ask what's not captured. Don't fabricate.

## Mode 3 — Session wrap (most accurate bullets)

The truest summary is written **while the session is still in context** — you saw
the work, including uncommitted debugging/research git never records. Do this when
the user signals they're wrapping up ("done for now", "eod", closing a task, or
long idle):

1. **Hours** — state your wall-clock estimate for confirmation. Ground it, don't
   guess: run `session-summary.py --latest 1` (or the day) and read the active
   hours off the current session. Subtract idle/breaks. "I have ~Xh active — right?"
2. **Bullets** — write **2–4 terse bullets of what was actually DONE** (not what was
   asked): landed changes, files/services touched, decisions, blockers. Pull from
   what happened this session, cross-checked against `edited:`/commits. No prose.
3. Confirm **Is it done?**, then write/close the row(s) — one per task/project, hours
   filled, `Done`/`In progress`/`Blocked`. Multi-project session → one row each,
   split by the script's per-project subtotal. Re-verify before overwriting a row.

This is the going-forward default; Mode 2 is the fallback for sessions with no wrap.

## Reports

On "the timesheet / my report / what did I do this week" → read the log, output
the range as the table (drop Notes unless asked), then per-day + range totals.
Flag days with no entry or only `In progress`.

To hand in a spreadsheet:
```bash
python3 "$HOME/.claude/timesheet-tools/scripts/export_csv.py"     # -> <TS>\activity-log.csv
python3 "$HOME/.claude/timesheet-tools/scripts/export_excel.py"   # -> <TS>\activity-log.xlsx (needs openpyxl)
```

## Rules

- Never invent tasks/hours — when unsure, ask.
- One row per task; confirm `Done` before marking it (that's how man-hours count).
- Terse entries; this is a log, not prose.
