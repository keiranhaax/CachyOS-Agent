# SPDX-License-Identifier: GPL-3.0-only
# A machine where opencode is signed in to Google (a Gemini sign-in under its
# "google" provider) but never set up the Antigravity plugin: that sign-in is
# not Antigravity's, so nothing here is in use and nothing is asked of Google.

import json

ROUTES = []


def setup(home, bin):
  data = home / ".local" / "share" / "opencode"
  data.mkdir(parents=True, exist_ok=True)
  (data / "auth.json").write_text(json.dumps({"google": {"type": "oauth", "access": "ya29.FAKE-GEMINI-NOT-AGY", "expires": 4102444800000}}))


def check(record, requests):
  assert requests == [], "a Gemini sign-in was sent to Google's Antigravity quota"
  assert record["ready"] is False and record["limits"] == [] and record["usageStatusText"] == "" and record["tierLabel"] == ""
