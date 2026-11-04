# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai monitor endpoint answers HTTP 500, with no earlier answer
# kept.

ENV = {"ZAI_API_KEY": "sk-FAKE-ZAI-DOWN"}
ROUTES = [("/api/monitor/usage/quota/limit", (500, {"msg": "internal error"}))]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["usageStatusText"] == "Z.ai limits unavailable", (record["ready"], record["usageStatusText"])
  assert record["authHelpText"] == "Z.ai's monitor endpoint returned HTTP 500. Local stats are still shown.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
  # The server answered, so there is no sooner retry to ask for.
  assert "retryAdvised" not in record
