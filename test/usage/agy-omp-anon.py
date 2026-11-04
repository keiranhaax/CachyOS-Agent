# SPDX-License-Identifier: GPL-3.0-only
# A machine with two omp Antigravity accounts, both lapsed, and an `omp usage`
# report that names no account: there is no telling whose it is. The limits
# are shown, but kept for neither account, no plan is asked of Google with a
# token that has lapsed, and the plan stays unknown.

import json
import os
import sqlite3
from pathlib import Path

LAPSED = {"type": "oauth", "access": "ya29.FAKE-OMP-A", "refresh": "1//FAKE-OMP-A", "expires": 1577836800000, "email": "a.user@example.test"}
OTHER = {"type": "oauth", "access": "ya29.FAKE-OMP-B", "refresh": "1//FAKE-OMP-B", "expires": 1577836800000, "email": "b.user@example.test"}
REPORT = {"reports": [{"provider": "google-antigravity", "limits": [
  {"label": "Gemini", "window": {"id": "5h", "resetsAt": "2099-04-01T05:00:00Z"}, "amount": {"usedFraction": 0.25}},
  {"label": "Gemini", "window": {"id": "weekly", "resetsAt": "2099-04-07T00:00:00Z"}, "amount": {"usedFraction": 0.75}},
]}]}
OMP = f"""#!/usr/bin/python3
import sys
if sys.argv[1:] != ["usage", "--json", "--provider", "google-antigravity"]:
  sys.exit(2)
print({json.dumps(REPORT)!r})
"""
ROUTES = []  # no token of either account is fresh


def setup(home, bin):
  tool = bin / "omp"
  tool.write_text(OMP)
  tool.chmod(0o755)
  database = home / ".omp" / "agent" / "agent.db"
  database.parent.mkdir(parents=True, exist_ok=True)
  database.unlink(missing_ok=True)
  conn = sqlite3.connect(database)
  with conn:
    conn.execute("CREATE TABLE auth_credentials (provider TEXT, credential_type TEXT, disabled_cause TEXT, data TEXT)")
    conn.executemany("INSERT INTO auth_credentials VALUES (?, ?, ?, ?)", [
      ("google-antigravity", "oauth", None, json.dumps(LAPSED)),
      ("google-antigravity", "oauth", None, json.dumps(OTHER)),
    ])
  conn.close()


def check(record, requests):
  assert requests == [], "a lapsed token was sent to Google"
  assert record["ready"] is True and record["tierLabel"] == "", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.25, "resetsAt": "2099-04-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.75, "resetsAt": "2099-04-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False and record["retryAdvised"] is False
  assert record["limitsFetchedAt"] > 0
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  assert list(cache.glob("agy-limits-*.json")) == [], "limits were kept for an account the report does not name"
