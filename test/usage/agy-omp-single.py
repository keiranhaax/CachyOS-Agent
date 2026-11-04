# SPDX-License-Identifier: GPL-3.0-only
# A machine with one omp Antigravity account, whose lapsed token omp renews
# when asked for usage (the stub does, in its database), and an `omp usage`
# report that names no account: it is the only one, so it is its, as renewed.
# Google's plan answer names no tier, so the plan is the one kept from the
# last good answer, and the new limits are kept for the account beside it.

import hashlib
import json
import os
import sqlite3
import time
from pathlib import Path

EMAIL = "single.user@example.test"
RENEWED_ACCESS = "ya29.FAKE-OMP-SINGLE-RENEWED"
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
LAPSED = {"type": "oauth", "access": "ya29.FAKE-OMP-SINGLE", "refresh": "1//FAKE-OMP-SINGLE", "expires": 1577836800000, "email": EMAIL}
RENEWED = dict(LAPSED, access=RENEWED_ACCESS, expires=4102444800000)
REPORT = {"reports": [{"provider": "google-antigravity", "limits": [
  {"label": "Gemini", "window": {"id": "weekly", "resetsAt": "2099-04-07T00:00:00Z"}, "amount": {"usedFraction": 0.5}},
]}]}
OMP = f"""#!/usr/bin/python3
import json, os, sqlite3, sys
if sys.argv[1:] != ["usage", "--json", "--provider", "google-antigravity"]:
  sys.exit(2)
conn = sqlite3.connect(os.path.join(os.environ["HOME"], ".omp", "agent", "agent.db"))
with conn:
  conn.execute("UPDATE auth_credentials SET data = ?", ({json.dumps(RENEWED)!r},))
print({json.dumps(REPORT)!r})
"""
ROUTES = [(BASE + "loadCodeAssist", {"cloudaicompanionProject": "single-project"})]


def kept_path():
  return Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"agy-limits-{hashlib.sha256(EMAIL.encode()).hexdigest()[:16]}.json"


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
    conn.execute("INSERT INTO auth_credentials VALUES ('google-antigravity', 'oauth', NULL, ?)", (json.dumps(LAPSED),))
  conn.close()
  kept_path().parent.mkdir(parents=True, exist_ok=True)
  kept_path().write_text(json.dumps({"fetchedAtMs": int((time.time() - 3 * 3600) * 1000), "tierLabel": "Ultra", "limits": [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.9, "resetsAt": "2099-01-01T05:00:00+00:00"},
  ]}))


def check(record, requests):
  # The renewed token is asked for the plan, and the quota comes from omp.
  assert [(r["url"], r["headers"]["authorization"]) for r in requests] == [(BASE + "loadCodeAssist", "Bearer " + RENEWED_ACCESS)], requests
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  assert record["limits"] == [{"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.5, "resetsAt": "2099-04-07T00:00:00+00:00"}], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False and record["retryAdvised"] is False
  kept = json.loads(kept_path().read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Ultra" and kept["fetchedAtMs"] == record["limitsFetchedAt"] > 0, kept
