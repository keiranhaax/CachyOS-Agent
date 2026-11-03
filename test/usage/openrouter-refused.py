# SPDX-License-Identifier: GPL-3.0-only
# A machine with an OpenRouter key in the environment that OpenRouter refuses.

ENV = {"OPENROUTER_API_KEY": "sk-or-FAKE-REVOKED"}

ROUTES = [
  ("/api/v1/key", (401, {"error": {"code": 401, "message": "No auth credentials found"}})),
  ("/api/v1/credits", (401, {"error": {"code": 401, "message": "No auth credentials found"}})),
]


def check(record, requests):
  # Still in use, but nothing could be read: the status asks for a new key.
  assert record["ready"] is True and record["tierLabel"] == "Prepaid" and record["limits"] == [] and "balance" not in record
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"].startswith("OpenRouter refused the API key. Set OPENROUTER_API_KEY"), record["authHelpText"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == 0
  assert "retryAdvised" not in record, "a refused key is no reason to retry soon"
  assert [r["url"] for r in requests] == ["https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer sk-or-FAKE-REVOKED" for r in requests)
