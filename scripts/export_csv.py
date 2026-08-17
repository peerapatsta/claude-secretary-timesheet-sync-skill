#!/usr/bin/env python3
"""Export activity-log.md -> activity-log.csv (a flat, diff-friendly view that
lives next to the markdown master).

The markdown table is the source of truth; this is a derived, spreadsheet-ready
copy. Written UTF-8 with BOM so Excel opens non-ASCII text correctly. A trailing
TOTAL row sums the Hours column.

Usage:
  python export_csv.py                       # paths from timesheet-config.json
  python export_csv.py --src X.md --out Y.csv
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tsconfig import data_root, log_path  # noqa: E402

HEADERS = ["Date", "Project", "Task", "Hours", "Status", "Notes"]


def parse_rows(src):
    rows = []
    with open(src, encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s.startswith("|"):
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) != 6:
                continue
            if cells[0] == "Date" or set(cells[0]) <= set("-: "):
                continue  # header row or separator
            rows.append(cells)
    rows.sort(key=lambda r: r[0])
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=log_path())
    ap.add_argument("--out", default=os.path.join(data_root(), "activity-log.csv"))
    a = ap.parse_args()

    if not os.path.exists(a.src):
        print(f"no log at {a.src} - is dataRoot set correctly? (python tsconfig.py)")
        return

    rows = parse_rows(a.src)
    total = 0.0
    for r in rows:
        try:
            total += float(r[3])
        except ValueError:
            pass

    with open(a.out, "w", encoding="utf-8-sig", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(HEADERS)
        w.writerows(rows)
        w.writerow(["", "", "TOTAL", round(total, 2), "", ""])

    print(f"Wrote {a.out}")
    print(f"{len(rows)} task rows, total hours = {round(total, 2)}")


if __name__ == "__main__":
    main()
