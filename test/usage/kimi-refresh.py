# SPDX-License-Identifier: GPL-3.0-only
# A machine with the legacy kimi-cli's sign-in in ~/.kimi, whose access token
# has lapsed: it is refreshed, the new tokens are written back, and the usage
# answer comes in the older shape (a weekly `usage` plus a list of `limits`).

import json
import os
import stat
import time
import urllib.parse
from pathlib import Path

OLD, NEW = "kimi-FAKE-OLD", "kimi-FAKE-NEW"

ROUTES = [
  ("/api/oauth/token", {"access_token": NEW, "refresh_token": "kimi-FAKE-REFRESH-2", "expires_in": 3600, "scope": "kimi-code", "token_type": "Bearer"}),
  ("/coding/v1/usages", {
    "usage": {"limit": "100", "used": "40", "resetTime": "2099-01-07T00:00:00Z"},
    "limits": [
      {"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"}, "detail": {"limit": "200", "remaining": "50", "resetTime": "2099-01-01T05:00:00Z"}},
      {"window": {"duration": 7, "timeUnit": "TIME_UNIT_DAY"}, "detail": {"limit": 10, "used": 10, "resetAt": "2099-01-07T00:00:00Z"}},
      {"name": "Agent swarm", "detail": {"limit": 8, "used": 2}},
    ],
  }),
]


def credentials(home):
  return home / ".kimi/credentials/kimi-code.json"


def setup(home, bin):
  credentials(home).parent.mkdir(parents=True, exist_ok=True)
  credentials(home).write_text(json.dumps({"access_token": OLD, "refresh_token": "kimi-FAKE-REFRESH-1", "expires_at": 1, "token_type": "Bearer"}))


def check(record, requests):
  assert record["ready"] is True, "not ready"
  assert [(r["method"], r["url"]) for r in requests] == [
    ("POST", "https://auth.kimi.com/api/oauth/token"), ("GET", "https://api.kimi.com/coding/v1/usages"),
  ], requests
  refresh, usages = requests
  assert urllib.parse.parse_qs(refresh["body"].decode()) == {
    "client_id": ["17e5f671-d194-4dfb-9706-5516cb48c098"], "grant_type": ["refresh_token"], "refresh_token": ["kimi-FAKE-REFRESH-1"],
  }, refresh["body"]
  assert refresh["headers"]["content-type"] == "application/x-www-form-urlencoded" and "authorization" not in refresh["headers"], refresh["headers"]
  assert usages["headers"]["authorization"] == "Bearer " + NEW, "the refreshed token was not the one sent"

  # The new sign-in is kept for the CLI, private to the user.
  path = credentials(Path(os.environ["HOME"]))
  saved = json.loads(path.read_text())
  assert (saved.get("access_token"), saved.get("refresh_token"), saved.get("scope")) == (NEW, "kimi-FAKE-REFRESH-2", "kimi-code"), "the credentials file was not updated"
  assert abs(saved.get("expires_at", 0) - (time.time() + 3600)) < 300, saved.get("expires_at")
  assert stat.S_IMODE(path.stat().st_mode) == 0o600 and stat.S_IMODE(path.parent.stat().st_mode) == 0o700, "the credentials are not private"

  assert record["limits"] == [
    {"label": "Weekly limit", "percent": 0.4, "resetsAt": "2099-01-07T00:00:00Z"},
    {"label": "Session (5-hour)", "percent": 0.75, "resetsAt": "2099-01-01T05:00:00Z"},
    {"label": "Weekly (7-day)", "percent": 1.0, "resetsAt": "2099-01-07T00:00:00Z"},
    {"label": "Agent swarm", "percent": 0.25, "resetsAt": ""},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False, (record["usageStatusText"], record["authHelpText"], record["limitsStale"])
  assert record["hasLocalStats"] is False and record["modelUsage"] == {} and record["totalPrompts"] == 0, "local stats on a machine with no sessions"
