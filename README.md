# claude-secretary-timesheet-sync-skill

A Claude Code skill that keeps your timesheet for you.

It logs every task you work on — project, task, hours, status — as you go, and
when you forget, it **reconstructs the missing days** from your git commits and
your Claude Code session transcripts. Your data stays yours: it lives in a
folder (or a private repo) that you point the installer at.

```
[BILLING] | 1h42m | ctx 61k/200k 31% | 139k left
```

```markdown
| Date       | Project | Task                                              | Hours | Status | Notes |
|------------|---------|---------------------------------------------------|-------|--------|-------|
| 2026-08-17 | BILLING | Invoice PDF renderer: fix rounding on line totals | 3.25  | Done   | PR #412 |
| 2026-08-17 | WEB     | Chased a flaky checkout e2e, no fix yet           | 1.5   | Blocked| debug |
```

## What you get

- **A session-start prompt.** Every new Claude Code session asks what you're
  working on, so a day is never silently lost.
- **A project in the status line.** Guessed from the working directory, pinned
  once you confirm it.
- **Grounded hours.** Read from the real transcript timeline — inter-message
  gaps, with an idle cap — not guessed by the model.
- **Backfill.** "Backfill since June 1" rebuilds unlogged days from commits +
  Claude activity, reconciles the two, and shows you proposed rows to approve.
- **Multi-machine (optional).** No repo needed to start — your log is just a
  folder. Add `-DataRepo` whenever a second computer shows up and the installer
  moves your history into it; each machine then exports its own activity file,
  so there is nothing to merge and hours across machines add up correctly.
- **CSV / XLSX export** for handing in.

Hours are never invented. If a number can't be grounded in a transcript or a
commit, Claude asks you instead of filling a blank.

## Install

Windows · PowerShell 5.1+ · Python 3 (python.org) · Claude Code.

```powershell
git clone https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill.git C:\tools\claude-secretary-timesheet-sync-skill
cd C:\tools\claude-secretary-timesheet-sync-skill
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Then edit `~\.claude\timesheet-config.json` to map your repos to project names,
and restart Claude Code.

**Full walkthrough: [INSTRUCTION.md](INSTRUCTION.md)** — including keeping the log
in your own private git repo, multi-machine sync, manual hook wiring, updating,
uninstalling, and troubleshooting.

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
  statusline-command.ps1 the status line
  set-project.ps1        pin the project for the status line
  sync-pull.ps1          SessionStart: pull your data repo
  sync-push.ps1          hourly task + SessionEnd: export, commit, push
  doctor.ps1             health check with per-failure fixes
templates/               seeds for a fresh data folder / data repo
```

## Privacy

Only **derived** fields are ever written to disk by the exporters: active
minutes, project, repo, branch, edited-file *names*, commit subjects, counts and
Claude's own session titles. Prompt and response text is never exported.

Your `activity-log.md` and `raw/` still describe your work in detail — if you put
them in a git repo, **make that repo private**.

## License

MIT — see [LICENSE](LICENSE).
