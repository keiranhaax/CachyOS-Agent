# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Vertex sign-in in agy's token file whose quota answer is HTTP 200 with
# an error object where the groups should be: an answer that cannot be read
# is a failed check, not a plan without quotas, and asking again sooner would
# not change it.

import json

BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
ROUTES = [
  (BASE + "loadCodeAssist", {"currentTier": {"id": "free-tier"}}),
  (BASE + "retrieveUserQuotaSummary", {"error": {"code": 500, "message": "internal"}}),
]


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({
    "access_token": "ya29.FAKE-GARBLED", "expiry": "2099-01-01T00:00:00Z", "auth_method": "vertex",
  }))


def check(record, requests):
  assert [r["url"].rsplit(":", 1)[1] for r in requests] == ["loadCodeAssist", "retrieveUserQuotaSummary"], requests
  # With no plan from a failed check, a Vertex account is a Cloud one.
  assert record["ready"] is True and record["tierLabel"] == "Cloud", record["tierLabel"]
  assert record["usageStatusText"] == "Antigravity limits unavailable", record["usageStatusText"]
  assert record["authHelpText"] == "Google's quota service sent an answer that couldn't be read.", record["authHelpText"]
  assert record["retryAdvised"] is False and record["limits"] == [] and record["limitsStale"] is False
