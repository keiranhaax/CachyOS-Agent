# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai key the monitor endpoint turns away with HTTP 403, and
# which has no earlier answer kept.

KEY = "sk-FAKE-ZAI-FORBIDDEN"

ENV = {"ZAI_API_KEY": KEY}
ROUTES = [("/api/monitor/usage/quota/limit", (403, {"msg": "forbidden", "success": False}))]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["usageStatusText"] == "Sign-in expired", (record["ready"], record["usageStatusText"])
  assert record["authHelpText"] == "Z.ai rejected the saved API key. Update it in ~/.config/cachyos-agent/zai.json or ZAI_API_KEY.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0 and record["tierLabel"] == ""
  assert "retryAdvised" not in record, "a refused key is not an outage to retry"
