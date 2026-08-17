#!/usr/bin/env python3
"""Per-session timesheet scaffolding from Claude Code transcripts (this machine).

Reads the full session transcripts under ~/.claude/projects/<cwd>/<id>.jsonl
(far richer than history.jsonl) and prints, per session:
  - precise active hours (inter-message gaps, idle-capped) attributed to the
    right project + git branch, so multi-project days split correctly
  - Claude's own aiTitle, files edited/written, commands run, first user prompt

This gives ACCURATE HOURS automatically. The bullets it prints are raw
material: turn them into truthful one-liners for the activity log (best done
live at session end while context is fresh - see the 'timesheet' skill wrap).

Project names, timezone and idle cap come from your timesheet-config.json;
see scripts/tsconfig.py.

Usage:
  python session-summary.py                     # latest session
  python session-summary.py --latest N          # N most recent sessions
  python session-summary.py --date 2026-07-31   # sessions active on a day
  python session-summary.py --since 2026-07-01 --until 2026-07-31
  python session-summary.py --all               # everything
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
from tsconfig import idle_cap, local_tz, proj_short, transcripts_dir  # noqa: E402

# Transcripts contain non-ASCII text; force UTF-8 stdout so Windows cp1252 doesn't choke.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

IDLE_CAP = idle_cap()
TAIL = 2 * 60          # seconds credited after the last message of a session
LOCAL_TZ = local_tz()


def parse_ts(s):
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(LOCAL_TZ)
    except Exception:
        return None


def load_session(path):
    """Return a dict of extracted facts for one transcript file, or None."""
    times, edits, cmds, prompts = [], [], [], []
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
                    prompts.append(c.strip())
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
                        elif name in ("Bash", "PowerShell") and inp.get("description"):
                            cmds.append(inp["description"])
    if not times:
        return None
    times.sort()
    active = TAIL
    for a, b in zip(times, times[1:]):
        active += min((b - a).total_seconds(), IDLE_CAP)
    return {
        "id": os.path.basename(path)[:8],
        "date": times[0].date(),
        "start": times[0], "end": times[-1],
        "hours": active / 3600.0,
        "msgs": len(times),
        "project": proj_short(cwd), "branch": branch, "title": title,
        "edits": edits, "cmds": cmds, "prompts": prompts,
    }


def dedupe(seq):
    seen, out = set(), []
    for x in seq:
        if x not in seen:
            seen.add(x); out.append(x)
    return out


def render(s):
    br = ""
    if s["branch"] and s["branch"] not in ("HEAD", "main", "master"):
        br = f"  [{s['branch']}]"
    print(f"SESSION {s['id']}  {s['date']}  {s['project']}{br}")
    print(f"  hours : {s['hours']:.2f}h active  "
          f"({s['start']:%H:%M}-{s['end']:%H:%M}, {s['msgs']} msgs, "
          f"idle-cap {IDLE_CAP // 60}m)")
    if s["title"]:
        print(f"  title : {s['title']}")
    files = dedupe(s["edits"])
    if files:
        shown = ", ".join(files[:12])
        if len(files) > 12:
            shown += f"  (+{len(files) - 12} more)"
        print(f"  edited: {len(files)} file(s): {shown}")
    if s["cmds"]:
        print(f"  ran   : {len(s['cmds'])} command(s)")
        for c in dedupe(s["cmds"])[:6]:
            print(f"          - {c}")
    if s["prompts"]:
        p = re.sub(r"\s+", " ", s["prompts"][0])[:140]
        print(f"  1st ask: {p}")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--latest", type=int, metavar="N")
    ap.add_argument("--date")
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()

    files = glob.glob(os.path.join(transcripts_dir(), "*", "*.jsonl"))
    if not files:
        print(f"no Claude Code transcripts found under {transcripts_dir()}")
        return
    sessions = [x for x in (load_session(f) for f in files) if x]
    sessions.sort(key=lambda s: s["start"])

    def d(x):
        return dt.date.fromisoformat(x) if x else None
    if a.date:
        day = d(a.date)
        sessions = [s for s in sessions if s["date"] == day]
    elif a.since or a.until:
        lo, hi = d(a.since) or dt.date.min, d(a.until) or dt.date.max
        sessions = [s for s in sessions if lo <= s["date"] <= hi]
    elif a.all:
        pass
    elif a.latest:
        sessions = sessions[-a.latest:]
    else:
        sessions = sessions[-1:]

    if not sessions:
        print("no sessions match.")
        return

    for s in sessions:
        render(s)

    # per day+project subtotal
    agg = defaultdict(float)
    for s in sessions:
        agg[(s["date"], s["project"])] += s["hours"]
    print("=== hours by day + project ===")
    total = 0.0
    for (day, proj), h in sorted(agg.items()):
        print(f"  {day}  {proj:<14} {h:6.2f}h")
        total += h
    print(f"  {'TOTAL':<30} {total:6.2f}h")


if __name__ == "__main__":
    main()
