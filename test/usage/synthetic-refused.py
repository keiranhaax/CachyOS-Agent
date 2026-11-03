# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Synthetic in pi, whose key (an environment reference,
# as pi allows) the service no longer accepts.

import json

ENV = {"SYNTHETIC_SECRET": "sk-FAKE-FROM-PI"}


def setup(home, bin):
  agent = home / ".pi" / "agent"
  agent.mkdir(parents=True, exist_ok=True)
  (agent / "auth.json").write_text(json.dumps({"synthetic": {"type": "api_key", "key": "$SYNTHETIC_SECRET"}}))


ROUTES = [("/v2/quotas", (401, {"error": "invalid api key"}))]


def check(record, requests):
  # A key makes it in use, though nothing else says so.
  assert record["ready"] is True and record["hasLocalStats"] is False and record["limits"] == []
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"].startswith("Synthetic rejected the API key"), record["authHelpText"]
  assert "retryAdvised" not in record
  assert [r["url"] for r in requests] == ["https://api.synthetic.new/v2/quotas"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer sk-FAKE-FROM-PI", "pi's key was not resolved and sent"
