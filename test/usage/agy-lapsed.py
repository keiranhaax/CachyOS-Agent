# SPDX-License-Identifier: GPL-3.0-only
# A machine whose agy sign-in (token file, with the token nested as agy keeps
# it) has an access token that lapsed with a refresh token behind it, and
# limits kept from three hours ago: the session window's reset has passed
# since, so it reads untouched, and the weekly one is still open. Nothing is
# asked of Google; agy refreshes its own token when it next runs.

import base64
import hashlib
import json
import os
import time
from pathlib import Path

EMAIL = "lapsed.user@example.test"
FETCHED = int((time.time() - 3 * 3600) * 1000)
ROUTES = []  # a lapsed token is never sent anywhere


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({
    "token": {"access_token": "ya29.FAKE-LAPSED", "refresh_token": "1//FAKE-LAPSED", "expiry": "2020-01-01T00:00:00Z"},
    "id_token": jwt({"email": EMAIL}),
  }))
  kept = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept.mkdir(parents=True, exist_ok=True)
  (kept / f"agy-limits-{hashlib.sha256(EMAIL.encode()).hexdigest()[:16]}.json").write_text(json.dumps({
    "fetchedAtMs": FETCHED, "tierLabel": "Ultra", "limits": [
      {"label": "Session (5-hour)", "title": "Session", "percent": 0.4, "resetsAt": "2020-01-01T05:00:00+00:00"},
      {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.7, "resetsAt": "2099-01-07T00:00:00+00:00"},
    ],
  }))


def check(record, requests):
  assert requests == [], "a lapsed token was sent to Google"
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "Limits paused", record["usageStatusText"]
  assert record["authHelpText"] == (
    "The Antigravity access token `agy` keeps has lapsed — showing the last known limits. Start `agy` to refresh it; signing in again is not needed."
  ), record["authHelpText"]
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.0, "resetsAt": ""},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.7, "resetsAt": "2099-01-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == FETCHED and record["retryAdvised"] is False
