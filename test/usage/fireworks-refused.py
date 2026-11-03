# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Fireworks key the service no longer accepts.

import json

ENV = {"FIREWORKS_API_KEY": "fw-FAKE-REVOKED"}


def setup(home, bin):
  config = home / ".config" / "cachyos-agent"
  config.mkdir(parents=True, exist_ok=True)
  (config / "fireworks.json").write_text(json.dumps({"accountId": "accounts/acme-co"}))


ROUTES = [
  ("/billingUsage", (401, {"code": 16, "message": "UNAUTHENTICATED"})),
  (":getBalance", (401, {"code": 16, "message": "UNAUTHENTICATED"})),
]


def check(record, requests):
  # Still in use, but nothing could be read: the status asks for a new key.
  assert record["ready"] is True and record["tierLabel"] == "Prepaid"
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"].startswith("Fireworks rejected the API key. Set FIREWORKS_API_KEY"), record["authHelpText"]
  assert record["limitsStale"] is True and "balance" not in record and record["hasLocalStats"] is False
  assert "retryAdvised" not in record, "a refused key is no reason to retry soon"
  assert [r["url"].split("?")[0] for r in requests] == [
    "https://api.fireworks.ai/v1/accounts/acme-co/billingUsage", "https://api.fireworks.ai/v1/accounts/acme-co:getBalance",
  ], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer fw-FAKE-REVOKED" for r in requests)
