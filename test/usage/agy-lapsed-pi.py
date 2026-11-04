# SPDX-License-Identifier: GPL-3.0-only
# A machine whose only Antigravity sign-in is pi's, with an access token that
# lapsed (pi writes its expiry in epoch milliseconds) and a refresh token
# behind it: pi renews it when it next runs, so the record waits for that and
# names pi, not agy.

import json

ROUTES = []  # a lapsed token is never sent anywhere


def setup(home, bin):
  auth = home / ".pi" / "agent" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"google-antigravity": {"type": "oauth", "access": "ya29.FAKE-PI-LAPSED", "refresh": "1//FAKE-PI", "expires": 1577836800000}}))


def check(record, requests):
  assert requests == [], "a lapsed token was sent to Google"
  assert record["ready"] is True
  assert record["usageStatusText"] == "Limits paused", record["usageStatusText"]
  assert record["authHelpText"] == "The Antigravity access token pi keeps has lapsed. Start pi to refresh it; signing in again is not needed.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["retryAdvised"] is False and record["tierLabel"] == ""
