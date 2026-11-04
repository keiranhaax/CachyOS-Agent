# SPDX-License-Identifier: GPL-3.0-only
# A machine with no key in the environment, the config file or a .env, whose pi
# auth.json holds a `zai` entry that is a command (pi resolves it, this cannot)
# and a `zhipu` one that is a variable, and whose omp auth.json holds a literal
# `zai` key from /login.

import json

KEY = "sk-FAKE-ZAI-OMP-LOGIN"


def setup(home, bin):
  pi = home / ".pi" / "agent"
  pi.mkdir(parents=True)
  (pi / "auth.json").write_text(json.dumps({
    "zai": {"type": "api_key", "key": "!pass show zai"},
    "zhipu": {"type": "api_key", "key": "$ZHIPU_API_KEY"},
  }))
  omp = home / ".omp" / "agent"
  omp.mkdir(parents=True)
  (omp / "auth.json").write_text(json.dumps({"zai": {"type": "api_key", "key": f" {KEY} "}}))


ROUTES = [("/api/monitor/usage/quota/limit", {
  "success": True,
  "data": {"level": "pro", "limits": [{"type": "CREDIT_LIMIT", "unit": 6, "number": 1, "percentage": 55, "nextResetTime": 4071513600000}]},
})]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert requests[0]["headers"]["authorization"] == KEY, "omp's literal key was not sent"
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert record["limits"] == [{"label": "Weekly (7-day)", "percent": 0.55, "resetsAt": "2099-01-08T00:00:00+00:00"}], record["limits"]
