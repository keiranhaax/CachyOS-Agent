# SPDX-License-Identifier: GPL-3.0-only
# A machine with one omp Antigravity account whose token has lapsed with a
# refresh token behind it, and an `omp usage` report whose limits are text
# where a list belongs: a report of another shape is no answer, not a plan
# without limits, so the record waits for omp to renew its own token.

import json
import sqlite3

LAPSED = {"type": "oauth", "access": "ya29.FAKE-OMP-GARBLED", "refresh": "1//FAKE-OMP-GARBLED", "expires": 1577836800000, "email": "garbled.user@example.test"}
REPORT = {"reports": [{"provider": "google-antigravity", "limits": "none"}]}
OMP = f"""#!/usr/bin/python3
import sys
if sys.argv[1:] != ["usage", "--json", "--provider", "google-antigravity"]:
  sys.exit(2)
print({json.dumps(REPORT)!r})
"""
ROUTES = []  # the lapsed token is never sent


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


def check(record, requests):
  assert requests == [], "a lapsed token was sent to Google"
  assert record["ready"] is True and record["limits"] == [] and record["tierLabel"] == ""
  assert record["usageStatusText"] == "Limits paused", record["usageStatusText"]
  assert record["authHelpText"] == "The Antigravity access token omp keeps has lapsed. Start omp to refresh it; signing in again is not needed.", record["authHelpText"]
  assert record["limitsStale"] is False and record["retryAdvised"] is False
