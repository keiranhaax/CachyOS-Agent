# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Cloud sign-in in agy's token file that cannot reach Google at all and
# has no earlier answer kept: there is nothing to show, the status says so,
# and a retry is worth advising since the connection, not Google, failed.

import json

ROUTES = []  # every request fails to connect


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  # No expiry named: Google can say whether the token still holds, so it is asked.
  (root / "antigravity-oauth-token").write_text(json.dumps({"access_token": "ya29.FAKE-OFFLINE", "auth_method": "cloud"}))


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"], requests
  # With no plan from Google, a Cloud account is a Cloud one.
  assert record["ready"] is True and record["tierLabel"] == "Cloud", record["tierLabel"]
  assert record["usageStatusText"] == "Antigravity limits unavailable", record["usageStatusText"]
  assert record["authHelpText"] == "Couldn't reach Google's quota service. Retrying shortly.", record["authHelpText"]
  assert record["retryAdvised"] is True
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
