# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Z.ai key and no route to Z.ai (the seconds after login before
# the network is up), with no earlier answer kept.

ENV = {"ZAI_API_KEY": "sk-FAKE-ZAI-OFFLINE"}


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["usageStatusText"] == "Z.ai limits unavailable", (record["ready"], record["usageStatusText"])
  assert record["authHelpText"] == "Couldn't reach Z.ai's monitor endpoint. Retrying shortly. Local stats are still shown.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
  assert record.get("retryAdvised") is True, "no sooner retry was asked for"
