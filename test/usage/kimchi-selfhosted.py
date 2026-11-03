# SPDX-License-Identifier: GPL-3.0-only
# A machine logged in to a self-hosted Kimchi (key in the environment, region
# and URL saved by the login) on the Enterprise plan, out of credits, with no
# budget set.

import json

ENV = {"KIMCHI_API_KEY": "kimchi-FAKE-SELFHOSTED"}


def setup(home, bin):
  config = home / ".config" / "kimchi"
  config.mkdir(parents=True, exist_ok=True)
  (config / "config.json").write_text(json.dumps({"region": "self-hosted", "selfHostedUrl": "https://kimchi.corp.example/"}))


ROUTES = [
  ("/v1/credits", {"serverless": True, "tier": "enterprise", "remaining": "0.00", "has_credits": False}),
  ("/v1/budget", {"period": {}, "budgets": []}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Enterprise", record["tierLabel"]
  assert record.get("balance") == {"remaining": 0.0, "funded": 0, "spent": 0, "currency": "USD", "estimated": False}, record.get("balance")
  assert record["limits"] == [], record["limits"]
  # The gateway throttles an account with no credits, and no funded figure raises that alarm in the balance.
  assert record["usageStatusText"] == "Out of credits", record["usageStatusText"]
  assert record["authHelpText"].startswith("Kimchi's gateway is rate limiting"), record["authHelpText"]
  assert record["limitsStale"] is False
  # The gateway is the host the login names, never Kimchi's own.
  assert [r["url"] for r in requests] == ["https://kimchi.corp.example/llm/v1/credits", "https://kimchi.corp.example/llm/v1/budget"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer kimchi-FAKE-SELFHOSTED" for r in requests)
