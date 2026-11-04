# SPDX-License-Identifier: GPL-3.0-only
# A machine with an Antigravity enterprise sign-in in agy's own token file
# (no keyring here), kept under AGY_DIR instead of ~/.gemini. Google names no
# plan and no usable project, so the plan is the account kind. The quota buckets are
# named by their display names, one past its allowance and one in thirds.

import hashlib
import json
import os
from pathlib import Path

ACCESS = "ya29.FAKE-ENTERPRISE-ACCESS"
REFRESH = "1//FAKE-ENTERPRISE-REFRESH"
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"

ROUTES = [
  (BASE + "loadCodeAssist", {"cloudaicompanionProject": "   "}),
  (BASE + "retrieveUserQuotaSummary", {"groups": [{"displayName": "Gemini", "buckets": [
    # A fraction past 1 is no negative use, and thirds round to four places.
    {"bucketId": "pool-a", "displayName": "Five-hour quota", "remainingFraction": 1.25, "resetTime": "2099-01-01T05:00:00Z"},
    {"bucketId": "pool-b", "displayName": "Weekly quota", "remainingFraction": 0.33333, "resetTime": "2099-01-07T00:00:00Z"},
  ]}]}),
]


def setup(home, bin):
  root = home / "agy-elsewhere"
  root.mkdir(parents=True, exist_ok=True)
  os.environ["AGY_DIR"] = str(root)
  (root / "antigravity-oauth-token").write_text(json.dumps({
    "access_token": ACCESS, "refresh_token": REFRESH, "expiry": "2099-01-01T00:00:00Z", "auth_method": "enterprise",
  }))
  # Where agy keeps things by default holds an older sign-in that must not be read.
  old = home / ".gemini" / "antigravity-cli"
  old.mkdir(parents=True, exist_ok=True)
  (old / "antigravity-oauth-token").write_text(json.dumps({"access_token": "ya29.FAKE-OLD", "expiry": "2099-01-01T00:00:00Z"}))


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Enterprise", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.0, "resetsAt": "2099-01-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.6667, "resetsAt": "2099-01-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False

  # A blank project is no project: the quota is asked with an empty body.
  assert [r["url"] for r in requests] == [BASE + "loadCodeAssist", BASE + "retrieveUserQuotaSummary"], requests
  assert [json.loads(r["body"]) for r in requests] == [{}, {}], [r["body"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer " + ACCESS for r in requests), "the token file's sign-in was not sent"

  # No email to name the account, so its refresh token does.
  digest = hashlib.sha256(REFRESH.encode()).hexdigest()[:16]
  kept = json.loads((Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"agy-limits-{digest}.json").read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "", kept
  assert record["hasLocalStats"] is False and record["totalPrompts"] == 0
