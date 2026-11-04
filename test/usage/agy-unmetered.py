# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to agy (token file) on a plan whose quota answer lists
# no windows at all: healthy, with no meters, not a failed check.

import json

BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
ROUTES = [
  (BASE + "loadCodeAssist", {"paidTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra for Business"}}),
  (BASE + "retrieveUserQuotaSummary", {}),
]


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({"access_token": "ya29.FAKE-UNMETERED", "expiry": "2099-01-01T00:00:00Z"}))


def check(record, requests):
  assert [r["url"].rsplit(":", 1)[1] for r in requests] == ["loadCodeAssist", "retrieveUserQuotaSummary"], requests
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  assert record["limits"] == [] and record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["limitsStale"] is False and record["retryAdvised"] is False and record["limitsFetchedAt"] > 0
