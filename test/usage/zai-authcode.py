# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai key is refused the way Z.ai usually does it: HTTP 200,
# with an authentication code in the body and no data (here "token expired").

KEY = "sk-FAKE-ZAI-EXPIRED"

ENV = {"ZAI_API_KEY": KEY}
ROUTES = [("/api/monitor/usage/quota/limit", {"code": 1003, "msg": "token expired", "success": False})]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["usageStatusText"] == "Sign-in expired", (record["ready"], record["usageStatusText"])
  assert record["authHelpText"] == "Z.ai rejected the saved API key. Update it in ~/.config/cachyos-agent/zai.json or ZAI_API_KEY.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0 and record["tierLabel"] == ""
  assert "retryAdvised" not in record
