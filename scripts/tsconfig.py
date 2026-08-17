#!/usr/bin/env python3
"""Shared config loader for the timesheet scripts.

Every per-user / per-org value (where the log lives, what a project is called,
which timezone you are in) comes from ONE json file so the scripts themselves
stay generic and update cleanly with `git pull`.

Lookup order for the config file:
  1. $CLAUDE_TIMESHEET_CONFIG
  2. ~/.claude/timesheet-config.json          <- what install.ps1 writes
  3. built-in defaults (dataRoot = ~/Documents/claude-timesheet)

Import from a sibling script with:

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from tsconfig import CFG, raw_dir, log_path, proj_short, local_tz, idle_cap
"""
import datetime as dt
import json
import os
import re

DEFAULTS = {
    "version": 1,
    "dataRoot": "",
    "toolsRoot": "",
    "machine": "",
    "timezoneOffsetHours": 7,
    "idleCapMinutes": 25,
    "lastSubmitted": "",
    "sync": {"enabled": False, "repoRoot": "", "autoPush": True},
    "projects": [],
    "git": {"authorPattern": "", "searchRoots": [], "hostMap": {}},
}


def config_path() -> str:
    env = os.environ.get("CLAUDE_TIMESHEET_CONFIG")
    if env:
        return os.path.expanduser(env)
    return os.path.expanduser(os.path.join("~", ".claude", "timesheet-config.json"))


def _strip_comments(d):
    """Drop the `_comment_*` keys that document config.example.json."""
    if isinstance(d, dict):
        return {k: _strip_comments(v) for k, v in d.items() if not k.startswith("_comment")}
    return d


def load() -> dict:
    cfg = json.loads(json.dumps(DEFAULTS))  # deep copy
    p = config_path()
    if os.path.exists(p):
        try:
            with open(p, encoding="utf-8-sig") as fh:
                user = _strip_comments(json.load(fh))
            for k, v in user.items():
                if isinstance(v, dict) and isinstance(cfg.get(k), dict):
                    cfg[k].update(v)
                else:
                    cfg[k] = v
        except Exception as e:  # a broken config must not break `--help`
            print(f"[tsconfig] WARNING: could not read {p}: {e}")
    if not cfg.get("dataRoot"):
        cfg["dataRoot"] = os.path.expanduser(os.path.join("~", "Documents", "claude-timesheet"))
    if not cfg.get("machine"):
        cfg["machine"] = os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME") or "unknown"
    cfg["dataRoot"] = os.path.expanduser(cfg["dataRoot"])
    return cfg


CFG = load()

# Compiled once: [(regex, short name), ...] in declaration order, first match wins.
_PROJECT_RULES = []
for _rule in CFG.get("projects") or []:
    try:
        _PROJECT_RULES.append((re.compile(_rule["match"], re.I), _rule["name"]))
    except Exception:
        pass


def data_root() -> str:
    return CFG["dataRoot"]


def raw_dir() -> str:
    return os.path.join(CFG["dataRoot"], "raw")


def log_path() -> str:
    return os.path.join(CFG["dataRoot"], "activity-log.md")


def machine() -> str:
    return CFG["machine"]


def local_tz() -> dt.timezone:
    return dt.timezone(dt.timedelta(hours=float(CFG.get("timezoneOffsetHours", 0))))


def idle_cap() -> int:
    """Seconds. Gaps longer than this are 'away', not work."""
    return int(CFG.get("idleCapMinutes", 25)) * 60


def proj_short(cwd: str) -> str:
    """Working directory -> short project name for the timesheet.

    Config rules first (first match wins); otherwise the last path segment, so
    an unconfigured repo still gets a usable name instead of '?'.
    """
    p = (cwd or "").replace("\\", "/").lower()
    for rx, name in _PROJECT_RULES:
        if rx.search(p):
            return name
    base = (cwd or "").replace("/", "\\").rstrip("\\").split("\\")[-1]
    return base[:18] if base else "?"


def repo_name(cwd: str) -> str:
    return (cwd or "").replace("/", "\\").rstrip("\\").split("\\")[-1]


def transcripts_dir() -> str:
    return os.path.expanduser(os.path.join("~", ".claude", "projects"))


if __name__ == "__main__":
    print(f"config file : {config_path()}"
          f"{'' if os.path.exists(config_path()) else '   (MISSING - using defaults)'}")
    print(f"dataRoot    : {data_root()}")
    print(f"  log       : {log_path()}   {'ok' if os.path.exists(log_path()) else 'MISSING'}")
    print(f"  raw       : {raw_dir()}")
    print(f"machine     : {machine()}")
    print(f"timezone    : UTC{CFG.get('timezoneOffsetHours'):+g}")
    print(f"idle cap    : {idle_cap() // 60} min")
    print(f"sync        : {'on -> ' + CFG['sync'].get('repoRoot', '') if CFG['sync'].get('enabled') else 'off (local only)'}")
    print(f"projects    : {len(_PROJECT_RULES)} rule(s)")
    for rx, name in _PROJECT_RULES:
        print(f"  {name:<16} <- /{rx.pattern}/")
