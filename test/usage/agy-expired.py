# SPDX-License-Identifier: GPL-3.0-only
# A machine whose agy sign-in (token file, flat) has an access token that
# lapsed with no refresh token behind it, and no limits kept: nothing to ask
# Google with, and signing in again is the way out.

import json

ROUTES = []  # a lapsed token is never sent anywhere


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  (root / "antigravity-oauth-token").write_text(json.dumps({"access_token": "ya29.FAKE-EXPIRED", "expiry": "2020-01-01T00:00:00Z"}))


def check(record, requests):
  assert requests == [], "a lapsed token was sent to Google"
  assert record["ready"] is True
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "The Antigravity sign-in `agy` keeps expired. Start `agy` to sign in again.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["retryAdvised"] is False and record["tierLabel"] == ""
