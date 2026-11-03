# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Grok on a unified-billing account whose credits
# answer holds no percentage, so the only limit is the monthly quota. No
# session has run yet.

import json

CREDITS = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
MONTHLY = "https://cli-chat-proxy.grok.com/v1/billing"
TOKEN = "xai-FAKE-MONTHLY-TOKEN"


def setup(home, bin):
  grok = home / ".grok"
  grok.mkdir(exist_ok=True)
  (grok / "auth.json").write_text(json.dumps({"https://auth.x.ai": {"key": TOKEN, "expires_at": "2099-01-01T00:00:00Z", "user_id": "user-FAKE-MONTHLY"}}))
  (grok / "settings_cache.json").write_text(json.dumps({"payload": json.dumps({"settings": {"subscription_tier_display": "SuperGrok Lite"}})}))


ROUTES = [
  (CREDITS, {"config": {"isUnifiedBillingUser": True, "currentPeriod": {"type": "BILLING_PERIOD_TYPE_MONTHLY", "end": "2027-01-01T00:00:00Z"}}}),
  (MONTHLY, {"config": {"monthlyLimit": 40, "used": 30, "billingPeriodEnd": "2027-01-01T00:00:00Z"}}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "SuperGrok Lite", (record["ready"], record["tierLabel"])
  assert record["limits"] == [{"label": "Monthly", "percent": 0.75, "resetsAt": "2027-01-01T00:00:00+00:00"}], record["limits"]
  assert record["limitsStale"] is False and record["limitsFetchedAt"] > 0
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["hasLocalStats"] is False and record["totalSessions"] == 0
  assert [r["url"] for r in requests] == [CREDITS, MONTHLY], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == f"Bearer {TOKEN}" for r in requests), "the sign-in was not sent"
