# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to agy (token file) whose quota answer is HTTP 200 with
# the Gemini group's buckets as text where a list belongs: an answer that
# cannot be read, not a plan whose windows are all unused.

import json

BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
ROUTES = [
  (BASE + "loadCodeAssist", {}),
  (BASE + "retrieveUserQuotaSummary", {"groups": [{"displayName": "Gemini", "buckets": "none"}]}),
]


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({"access_token": "ya29.FAKE-GARBLED", "expiry": "2099-01-01T00:00:00Z"}))


def check(record, requests):
  assert [r["url"].rsplit(":", 1)[1] for r in requests] == ["loadCodeAssist", "retrieveUserQuotaSummary"], requests
  assert record["usageStatusText"] == "Antigravity limits unavailable", record["usageStatusText"]
  assert record["authHelpText"] == "Google's quota service sent an answer that couldn't be read.", record["authHelpText"]
  assert record["retryAdvised"] is False and record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
