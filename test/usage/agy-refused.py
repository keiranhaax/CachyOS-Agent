# SPDX-License-Identifier: GPL-3.0-only
# A machine whose only Antigravity sign-in is opencode's plugin, which Google
# refuses (403 on the quota, after the plan answered): the sign-in has been
# revoked, so the record says to start opencode and sign in again, and keeps
# showing the limits from two hours ago, marked stale. opencode's sign-in
# names no email, so those are kept under its refresh token. agy's own token
# file, which holds a refresh token and no access token, is never asked.

import hashlib
import json
import os
import time
from pathlib import Path

REFRESH = "1//FAKE-OPENCODE-REFUSED"
FETCHED = int((time.time() - 2 * 3600) * 1000)
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
ROUTES = [
  (BASE + "loadCodeAssist", {"cloudaicompanionProject": "refused-project"}),
  (BASE + "retrieveUserQuotaSummary", (403, {"error": {"code": 403, "status": "PERMISSION_DENIED"}})),
]


def setup(home, bin):
  agy = home / ".gemini" / "antigravity-cli"
  agy.mkdir(parents=True, exist_ok=True)
  (agy / "antigravity-oauth-token").write_text(json.dumps({"refresh_token": "1//FAKE-ONLY-REFRESH"}))
  config = home / ".config" / "opencode"
  config.mkdir(parents=True, exist_ok=True)
  (config / "antigravity-accounts.json").write_text(json.dumps({"version": 1, "accounts": []}))
  data = home / ".local" / "share" / "opencode"
  data.mkdir(parents=True, exist_ok=True)
  (data / "auth.json").write_text(json.dumps({"google": {"type": "oauth", "access": "ya29.FAKE-OPENCODE-REFUSED", "refresh": REFRESH, "expires": 4102444800000}}))
  kept = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept.mkdir(parents=True, exist_ok=True)
  (kept / f"agy-limits-{hashlib.sha256(REFRESH.encode()).hexdigest()[:16]}.json").write_text(json.dumps({
    "fetchedAtMs": FETCHED, "tierLabel": "Ultra", "limits": [
      {"label": "Session (5-hour)", "title": "Session", "percent": 0.4, "resetsAt": "2099-01-01T05:00:00+00:00"},
    ],
  }))


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Google refused the Antigravity sign-in opencode keeps. Start opencode to sign in again.", record["authHelpText"]
  assert record["limits"] == [{"label": "Session (5-hour)", "title": "Session", "percent": 0.4, "resetsAt": "2099-01-01T05:00:00+00:00"}], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == FETCHED and record["retryAdvised"] is False
  assert [r["url"].rsplit(":", 1)[1] for r in requests] == ["loadCodeAssist", "retrieveUserQuotaSummary"], requests
  assert json.loads(requests[1]["body"]) == {"project": "refused-project"}, requests[1]["body"]
