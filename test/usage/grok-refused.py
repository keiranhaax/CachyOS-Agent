# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Grok home is GROK_HOME, signed in with a token xAI turns
# away before it has lapsed, and no earlier answer kept.

import json
import os

CREDITS = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
TOKEN = "xai-FAKE-REFUSED-TOKEN"


def setup(home, bin):
  grok = home / "elsewhere" / "grok"
  grok.mkdir(parents=True, exist_ok=True)
  os.environ["GROK_HOME"] = str(grok)
  (grok / "auth.json").write_text(json.dumps({"https://auth.x.ai": {"key": TOKEN, "expires_at": "2099-01-01T00:00:00Z", "user_id": "user-FAKE-REFUSED"}}))
  (grok / "settings_cache.json").write_text(json.dumps({"payload": json.dumps({"settings": {"subscription_tier_display": "SuperGrok"}})}))


ROUTES = [("v1/billing", (401, {"code": 16, "message": "unauthenticated"}))]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "SuperGrok", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "xAI refused Grok's saved sign-in. Start Grok, or run `grok login`, to sign in again.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
  # A refusal is final: neither the monthly quota nor a retry is asked.
  assert [r["url"] for r in requests] == [CREDITS], [r["url"] for r in requests]
  assert requests[0]["headers"]["authorization"] == f"Bearer {TOKEN}", "the sign-in was not sent"
