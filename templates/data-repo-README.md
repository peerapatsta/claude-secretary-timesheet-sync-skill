# My timesheet data

Personal work log kept by [claude timesheet secretary](https://github.com/peerapatsta/claude-secretary-timesheet-sync-skill).

**Keep this repository PRIVATE.** It contains your real hours, the repos and
branches you worked on, the file names you edited and your commit subjects.

```
timesheet/
├── activity-log.md          the log you actually submit (markdown table)
├── activity-log.csv         derived flat view (export_csv.py)
└── raw/<MACHINE>/YYYY-MM.jsonl   auto-collected activity, one file per machine
```

`raw/` holds **derived fields only** — active minutes, project, repo, branch,
edited-file names, commit subjects, counts, session titles. Prompt and response
text is never written here.

One machine writes one `raw/<MACHINE>/` file, so git never has to merge raw data.

## Adding another machine

```powershell
git clone <this repo> C:\path\to\data
cd C:\path\to\claude-secretary-timesheet-sync-skill          # the public tools repo
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DataRepo C:\path\to\data
```
