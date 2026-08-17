#!/usr/bin/env python3
"""Export THIS machine's Claude Code activity to a machine-namespaced JSONL so
the timesheet can be reconciled across machines.

Reads the full session transcripts under ~/.claude/projects/<cwd>/<id>.jsonl and
writes one line PER SESSION to:

    <dataRoot>/raw/<MACHINE>/<YYYY-MM>.jsonl

Only DERIVED fields are written (active minutes, project, repos, edited-file
names, commit subjects, counts, aiTitle) - NEVER raw prompt/response text - so
even a synced data repo stays free of conversation content.

Single writer per file (this machine only) => git never has to merge raw data.
Idempotent: re-running upserts sessions by id and rewrites the month file sorted,
so the hourly scheduled task can run as often as it likes.

dataRoot, project names, timezone and idle cap come from your
timesheet-config.json; see scripts/tsconfig.py.

Usage:
  python export_activity.py                 # current month
  python export_activity.py --month 2026-07
  python export_activity.py --since 2026-05-30 --until 2026-07-31
  python export_activity.py --all
  python export_activity.py --machine NAME   # override the configured machine id
  python export_activity.py --stdout         # print, don't write (dry run)
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tsconfig import (idle_cap, local_tz, machine, proj_short,  # noqa: E402
                      raw_dir, repo_name, transcripts_dir)

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

IDLE_CAP = idle_cap()
TAIL = 2 * 60
LOCAL_TZ = local_tz()

# git commit -m "subject"  /  git commit -m 'subject'  (best-effort subject grab)
_COMMIT_RE = re.compile(r"""git\s+commit\b[^\n]*?-m\s+(['"])(.+?)\1""", re.S)


def parse_ts(s):
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(LOCAL_TZ)
    except Exception:
        return None


def dedupe(seq):
    seen, out = set(), []
    for x in seq:
        if x and x not in seen:
            seen.add(x); out.append(x)
    return out


def load_session(path):
    """Derived facts for one transcript, or None if it has no activity."""
    times, edits, cmds, commits, prompts = [], [], [], [], []
    cwd = branch = title = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get("type")
            if d.get("cwd"):
                cwd = d["cwd"]
            if d.get("gitBranch"):
                branch = d["gitBranch"]
            if t == "ai-title" and d.get("aiTitle"):
                title = d["aiTitle"]
            ts = parse_ts(d.get("timestamp"))
            if ts:
                times.append(ts)
            msg = d.get("message") or {}
            if t == "user":
                c = msg.get("content")
                if isinstance(c, str) and c and not c.startswith("<"):
                    prompts.append(1)  # count only; text is NOT stored
            elif t == "assistant":
                c = msg.get("content")
                if isinstance(c, list):
                    for b in c:
                        if not isinstance(b, dict) or b.get("type") != "tool_use":
                            continue
                        name = b.get("name")
                        inp = b.get("input") or {}
                        if name in ("Edit", "Write", "NotebookEdit") and inp.get("file_path"):
                            edits.append(os.path.basename(inp["file_path"]))
                        elif name in ("Bash", "PowerShell"):
                            if inp.get("description"):
                                cmds.append(inp["description"])
                            for m in _COMMIT_RE.finditer(inp.get("command") or ""):
                                subj = m.group(2).splitlines()[0].strip()
                                if subj:
                                    commits.append(subj[:120])
    if not times:
        return None
    times.sort()
    active = TAIL
    for a, b in zip(times, times[1:]):
        active += min((b - a).total_seconds(), IDLE_CAP)
    files = dedupe(edits)
    return {
        "machine": None,  # filled by caller
        "session": os.path.basename(path)[:8],
        "date": times[0].date().isoformat(),
        "project": proj_short(cwd),
        "repo": repo_name(cwd),
        "branch": branch if branch not in ("HEAD", "main", "master") else None,
        "first": times[0].strftime("%H:%M"),
        "last": times[-1].strftime("%H:%M"),
        "active_min": round(active / 60.0),
        "prompts": len(prompts),
        "files_touched": len(files),
        "files": files[:15],
        "commits": dedupe(commits)[:10],
        "summary": title or "",
    }


def in_range(date_iso, lo, hi):
    d = dt.date.fromisoformat(date_iso)
    return lo <= d <= hi


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--month", help="YYYY-MM (default: current month)")
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--machine", default=machine())
    ap.add_argument("--stdout", action="store_true", help="print instead of writing files")
    a = ap.parse_args()

    if a.all:
        lo, hi = dt.date.min, dt.date.max
    elif a.since or a.until:
        lo = dt.date.fromisoformat(a.since) if a.since else dt.date.min
        hi = dt.date.fromisoformat(a.until) if a.until else dt.date.max
    else:
        month = a.month or dt.date.today().strftime("%Y-%m")
        y, m = map(int, month.split("-"))
        lo = dt.date(y, m, 1)
        hi = dt.date(y + (m == 12), (m % 12) + 1, 1) - dt.timedelta(days=1)

    files = glob.glob(os.path.join(transcripts_dir(), "*", "*.jsonl"))
    sessions = []
    for f in files:
        s = load_session(f)
        if s and in_range(s["date"], lo, hi):
            s["machine"] = a.machine
            sessions.append(s)

    if not sessions:
        print(f"no sessions in range for machine {a.machine}")
        return

    # bucket by month file
    by_month = defaultdict(dict)  # "YYYY-MM" -> {session_id: record}
    for s in sessions:
        by_month[s["date"][:7]][s["session"]] = s

    if a.stdout:
        for s in sorted(sessions, key=lambda x: (x["date"], x["first"])):
            print(json.dumps(s, ensure_ascii=False))
        return

    out_dir = os.path.join(raw_dir(), a.machine)
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for ym, recs in by_month.items():
        path = os.path.join(out_dir, f"{ym}.jsonl")
        # upsert: merge with existing so a narrow run never drops prior sessions
        merged = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        r = json.loads(line)
                        merged[r.get("session")] = r
                    except Exception:
                        pass
        merged.update(recs)
        ordered = sorted(merged.values(), key=lambda x: (x.get("date", ""), x.get("first", "")))
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            for r in ordered:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
        total += len(recs)
        print(f"wrote {len(recs):3d} session(s) (file now {len(ordered)}) -> {path}")
    print(f"done: {total} session(s) exported for {a.machine}")


if __name__ == "__main__":
    main()
