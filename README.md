# claude-secretary-timesheet-sync-skill

A Claude Code skill that keeps your timesheet for you.

It logs every task you work on — project, task, hours, status — as you go, and
when you forget, it **reconstructs the missing days** from your git commits and
your Claude Code session transcripts.

```
[BILLING] | 1h42m | ctx 61k/200k 31% | 139k left
```

```markdown
| Date       | Project | Task                                              | Hours | Status | Notes |
|------------|---------|---------------------------------------------------|-------|--------|-------|
| 2026-08-17 | BILLING | Invoice PDF renderer: fix rounding on line totals | 3.25  | Done   | PR #412 |
| 2026-08-17 | WEB     | Chased a flaky checkout e2e, no fix yet           | 1.5   | Blocked| debug |
```

---

# ⚡ Two modes — pick one at install time

Both modes give you **every feature listed below**. The only difference is
*where your log lives* and whether several computers share it.

### 🖥️ Mode 1 — Solo (offline)

**No git. No account. No repo.** Your log is a plain folder at
`<Documents>\claude-timesheet-data\`.

```powershell
.\install.ps1
```

*Best for: one computer. Start here if you're not sure.*

### 🔄 Mode 2 — Multi-sync

**Your own private git repo.** Log and activity live in `<your-repo>\timesheet\`,
shared by every computer you work on.

```powershell
.\install.ps1 -DataRepo "https://github.com/you/my-timesheet-data.git"
```

*Best for: laptop + desktop — or anyone who wants their hours backed up and versioned.*

### Side by side

| | 🖥️ Solo (offline) | 🔄 Multi-sync |
|---|:---:|:---:|
| Session prompt + status line | ✅ | ✅ |
| Measured hours from transcripts | ✅ | ✅ |
| Backfill from git + Claude history | ✅ | ✅ |
| Reports · CSV / Excel export | ✅ | ✅ |
| Needs git or an account | — | private repo you own |
| One log across several computers | ❌ | ✅ |
| Hours added up per machine | ❌ | ✅ |
| Auto pull on session start · hourly push | ❌ | ✅ |
| Version history of your hours | ❌ | ✅ |

> **Switching is free.** Run the installer again with `-DataRepo` and it *moves*
> your existing `activity-log.md` and `raw\` exports into the repo. Nothing is
> lost, so you never have to decide up front.

**→ Step-by-step setup and daily use: [INSTRUCTION.md](INSTRUCTION.md)**

---

## What it does

**Asks, so a day is never silently lost.** Every new Claude Code session opens
with a banner asking what you're working on. Answer it and a row opens.

**Shows the project you're on.** The status line guesses your project from the
folder and marks it `[BILLING?]`; once you confirm, the `?` drops off.

**Measures your hours instead of guessing them.** Hours come from the real
transcript timeline — gaps between messages, with an idle cap so lunch doesn't
count. Split per project and per branch, so a three-project day lands as three
correct rows.

**Rebuilds days you forgot to log.** Say *"backfill since June 1"* and it reads
your git commits (what landed) and your Claude activity (what the time actually
went to), reconciles the two, and shows you proposed rows to approve.

**Answers "what did I do this week?"** with the table plus per-day and range
totals, flagging days that are empty or still `In progress`.

**Hands in a spreadsheet.** One command for `.csv`, one for a formatted `.xlsx`.

**Never invents hours.** If a number can't be grounded in a transcript or a
commit, Claude asks you instead of filling in a blank.

## Install

Windows · PowerShell 5.1+ · Python 3 (from python.org) · Claude Code · git (Mode 2 only)

```powershell
git clone https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill.git C:\tools\claude-secretary-timesheet-sync-skill
cd C:\tools\claude-secretary-timesheet-sync-skill

powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1                       # Mode 1
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo <url|path>  # Mode 2
```

Then edit `~\.claude\timesheet-config.json` to map your repos to project names,
and restart Claude Code. Full walkthrough in **[INSTRUCTION.md](INSTRUCTION.md)**.

## Where things live

| Path | What |
|---|---|
| `~\.claude\timesheet-tools` | → this repo (junction) |
| `~\.claude\timesheet-data` | → your log + `raw\<MACHINE>\` activity (junction) |
| `~\.claude\skills\timesheet` | → `skills\timesheet` (junction) |
| `~\.claude\timesheet-config.json` | everything you customise |

Nothing in the skill or the scripts hardcodes a username, so the same commands
work on every machine and for every user.

## Repo layout

```
install.ps1              per-machine installer (idempotent, backs up first)
uninstall.ps1            removes links/hooks/task — never your data
config.example.json      every setting, documented
skills/timesheet/        the skill Claude actually reads
scripts/
  tsconfig.py/.ps1       shared config loader (the only place settings are read)
  session-summary.py     per-session hours + bullets, this machine
  export_activity.py     derived activity -> raw/<machine>/YYYY-MM.jsonl
  reconcile.py           merge every machine's raw -> proposed rows
  export_csv.py          activity-log.md -> .csv
  export_excel.py        activity-log.md -> .xlsx (needs openpyxl)
  session-reminder.ps1   SessionStart banner + instruction
  check-update.ps1       daily "newer version upstream?" notice (time-boxed)
  statusline-command.ps1 the status line
  set-project.ps1        pin the project for the status line
  sync-pull.ps1          SessionStart: pull your data repo      (Mode 2)
  sync-push.ps1          hourly task + SessionEnd: export, commit, push (Mode 2)
  doctor.ps1             health check with per-failure fixes
templates/               seeds for a fresh data folder / data repo
```

## Privacy

Only **derived** fields are ever written by the exporters: active minutes,
project, repo, branch, edited-file *names*, commit subjects, counts and Claude's
own session titles. Prompt and response text is never exported.

Your `activity-log.md` and `raw/` still describe your work in detail — in Mode 2,
**make that repo private**.

## License

MIT — see [LICENSE](LICENSE).
