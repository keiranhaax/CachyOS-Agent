# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Kimchi key in the environment that the gateway refuses on
# both endpoints, and nothing remembered from an earlier run.

ENV = {"KIMCHI_API_KEY": "kimchi-FAKE-REVOKED"}

ROUTES = [
  ("/v1/credits", (401, {"error": "invalid api key"})),
  ("/v1/budget", (401, {"error": "invalid api key"})),
]


def check(record, requests):
  # A key makes it in use. Nothing was read, so there is no plan, balance or window to show.
  assert record["ready"] is True and record["tierLabel"] == "" and record["limits"] == [] and "balance" not in record
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"].startswith("Kimchi rejected its API key"), record["authHelpText"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == 0 and record["hasLocalStats"] is False
  assert "retryAdvised" not in record, "a refused key is no reason to retry soon"
  # With no region named the key goes to the US gateway, and only there.
  assert [r["url"] for r in requests] == ["https://llm.kimchi.dev/v1/credits", "https://llm.kimchi.dev/v1/budget"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer kimchi-FAKE-REVOKED" for r in requests)
