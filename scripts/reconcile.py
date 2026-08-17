#!/usr/bin/env python3
"""Merge every machine's raw activity into proposed activity-log rows.

Reads  <dataRoot>/raw/*/*.jsonl  (all machines) for a date range and groups by
day + project. Hours come from Claude active minutes recorded per session:

  - within one machine, a day's hours = sum of that machine's session minutes;
  - across machines on the same day, hours are ADDITIVE (you can't be on two
    machines at once, so different machines = genuinely different work blocks).

Prints a markdown table of proposed rows plus the bullet material (session
titles, commit subjects, files) so the 'timesheet' skill can turn them into
truthful one-liners and confirm before writing activity-log.md. It NEVER writes
the log itself.

Only meaningful with sync on (each machine commits its own raw/<machine>/ file);
`git pull` first so you have every machine's latest export.

Usage:
  python reconcile.py --since 2026-05-30 --until 2026-07-31
  python reconcile.py --date 2026-07-31
  python reconcile.py                       # last 14 days
"""
import argparse
import datetime as dt
import glob
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tsconfig import raw_dir  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def quarter(hours):
    return round(hours * 4) / 4.0


def dedupe(seq):
    seen, out = set(), []
    for x in seq:
        if x and x not in seen:
            seen.add(x); out.append(x)
    return out


def load(lo, hi):
    rows = []
    for path in glob.glob(os.path.join(raw_dir(), "*", "*.jsonl")):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                d = r.get("date")
                if not d:
                    continue
                if lo <= dt.date.fromisoformat(d) <= hi:
                    rows.append(r)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--date")
    a = ap.parse_args()

    if a.date:
        lo = hi = dt.date.fromisoformat(a.date)
    else:
        hi = dt.date.fromisoformat(a.until) if a.until else dt.date.today()
        lo = dt.date.fromisoformat(a.since) if a.since else hi - dt.timedelta(days=14)

    rows = load(lo, hi)
    if not rows:
        print(f"no raw activity between {lo} and {hi} under {raw_dir()}. "
              f"Run export_activity.py on each machine first (and `git pull`).")
        return

    # (date, project) -> aggregate;  track per-machine minutes for the additive note
    agg = defaultdict(lambda: {"min_by_machine": defaultdict(int), "titles": [],
                               "commits": [], "files": [], "prompts": 0,
                               "repos": set(), "machines": set()})
    for r in rows:
        key = (r["date"], r.get("project", "?"))
        g = agg[key]
        g["min_by_machine"][r.get("machine", "?")] += r.get("active_min", 0)
        g["prompts"] += r.get("prompts", 0)
        g["machines"].add(r.get("machine", "?"))
        if r.get("repo"):
            g["repos"].add(r["repo"])
        if r.get("summary"):
            g["titles"].append(r["summary"])
        g["commits"] += r.get("commits", [])
        g["files"] += r.get("files", [])

    print(f"# Proposed rows  {lo} -> {hi}\n")
    print("| Date | Project | Hours | Machines | Notes |")
    print("|------|---------|-------|----------|-------|")
    day_total = defaultdict(float)
    for (date, proj), g in sorted(agg.items()):
        hours = quarter(sum(g["min_by_machine"].values()) / 60.0)
        day_total[date] += hours
        machines = "+".join(sorted(g["machines"]))
        note = f"{g['prompts']} prompts"
        if len(g["machines"]) > 1:
            per = ", ".join(f"{m}:{quarter(v / 60.0)}h"
                            for m, v in sorted(g["min_by_machine"].items()))
            note += f"; additive ({per})"
        print(f"| {date} | {proj} | {hours} | {machines} | {note} |")

    print("\n## bullet material (turn into truthful one-liners, do NOT paste verbatim)\n")
    for (date, proj), g in sorted(agg.items()):
        print(f"### {date}  {proj}   ({'+'.join(sorted(g['machines']))})")
        if g["repos"]:
            print(f"  repos : {', '.join(sorted(g['repos']))}")
        for t in dedupe(g["titles"])[:8]:
            print(f"  title : {t}")
        for c in dedupe(g["commits"])[:12]:
            print(f"  commit: {c}")
        files = dedupe(g["files"])
        if files:
            shown = ", ".join(files[:15])
            if len(files) > 15:
                shown += f"  (+{len(files) - 15})"
            print(f"  files : {shown}")
        print()

    print("=== hours by day (all machines, additive) ===")
    grand = 0.0
    for date, h in sorted(day_total.items()):
        print(f"  {date}  {h:6.2f}h")
        grand += h
    print(f"  {'TOTAL':<12}{grand:6.2f}h")


if __name__ == "__main__":
    main()
