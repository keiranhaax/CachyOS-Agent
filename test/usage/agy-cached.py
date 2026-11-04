# SPDX-License-Identifier: GPL-3.0-only
# The panel's refresh, not a person's: a machine signed in to agy (token
# file) whose answer from Google is five seconds old. Without --force that is
# reused, so a panel opened and shut repeatedly does not become a request per
# flick.

import base64
import hashlib
import json
import os
import time
from pathlib import Path

EMAIL = "cached.user@example.test"
FETCHED = int((time.time() - 5) * 1000)
ARGS = []
ROUTES = []  # asking Google would fail to connect


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({
    "access_token": "ya29.FAKE-CACHED", "expiry": "2099-01-01T00:00:00Z", "id_token": jwt({"email": EMAIL}),
  }))
  kept = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept.mkdir(parents=True, exist_ok=True)
  (kept / f"agy-limits-{hashlib.sha256(EMAIL.encode()).hexdigest()[:16]}.json").write_text(json.dumps({
    "fetchedAtMs": FETCHED, "tierLabel": "Pro", "limits": [
      {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.45, "resetsAt": "2099-01-07T00:00:00+00:00"},
    ],
  }))


def check(record, requests):
  assert requests == [], "a fresh answer was asked for again"
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert record["limits"] == [{"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.45, "resetsAt": "2099-01-07T00:00:00+00:00"}], record["limits"]
  # Reused is still live: nothing went wrong, so nothing is stale.
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == FETCHED
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["retryAdvised"] is False
