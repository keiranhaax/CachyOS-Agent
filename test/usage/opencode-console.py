# SPDX-License-Identifier: GPL-3.0-only
# A machine running opencode V2, whose database holds a Go key that the usage
# endpoint now refuses, a deactivated older key, and the Console session
# opencode signed in with, which is the one that answers (in the other
# deployment's field names). Its sessions are in V2's message table.

import json
import sqlite3
from datetime import datetime, timedelta, timezone

NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)


def ms(moment):
  return int(moment.timestamp() * 1000)


def message(provider, model, moment, tokens, cache=(0, 0)):
  # An opencode V2 `session_message` row's data: the model is nested.
  return json.dumps({
    "model": {"providerID": provider, "id": model},
    "time": {"created": ms(moment)},
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": 0, "cache": {"read": cache[0], "write": cache[1]}},
  })


CREDENTIALS = [
  ("opencode-go", {"type": "key", "key": "sk-FAKE-STORE-GO"}, 1),
  ("opencode-go", {"type": "key", "key": "sk-FAKE-STORE-OLD"}, 0),
  ("opencode", {"type": "oauth", "access": "FAKE-CONSOLE-ACCESS", "refresh": "FAKE-CONSOLE-REFRESH", "expires": ms(NOON + timedelta(days=30)), "metadata": {"orgID": "org_FAKE"}}, 1),
]

# A typed prompt and two steps answering it: the first books the prompt.
SESSION_MESSAGES = [
  ("msg_u1", "user", NOON, json.dumps({"time": {"created": ms(NOON)}})),
  ("msg_a1", "assistant", NOON + timedelta(minutes=1), message("opencode-go", "glm-5", NOON + timedelta(minutes=1), (60, 40), (100, 0))),
  ("msg_a2", "assistant", NOON + timedelta(minutes=2), message("opencode-go", "glm-5", NOON + timedelta(minutes=2), (5, 5))),
]

ROUTES = [
  ("/zen/go/v1/usage", (401, {"error": "unauthorized"})),
  ("/inference/go/v1/usage", {
    "rollingUsage": {"usagePercent": 10, "resetInSec": 3600},
    "weeklyUsage": {"usagePercent": 20, "resetInSec": 86400},
    "monthlyUsage": {"usagePercent": 30, "resetInSec": 0},
  }),
]


def setup(home, bin):
  db = home / ".local/share/opencode/opencode.db"
  db.parent.mkdir(parents=True, exist_ok=True)
  db.unlink(missing_ok=True)
  conn = sqlite3.connect(db)
  with conn:
    conn.execute("CREATE TABLE credential (integration_id TEXT NOT NULL, value TEXT NOT NULL, active INTEGER NOT NULL, time_updated INTEGER NOT NULL)")
    conn.executemany("INSERT INTO credential VALUES (?, ?, ?, 0)", [(integration, json.dumps(value), active) for integration, value, active in CREDENTIALS])
    conn.execute("CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
    conn.executemany("INSERT INTO session_message VALUES (?, 'ses_v', ?, ?, ?)", [(mid, kind, ms(moment), data) for mid, kind, moment, data in SESSION_MESSAGES])
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Go", (record["ready"], record["tierLabel"])
  # The refused key first, then the Console session on its own endpoint and
  # workspace; the deactivated key is never sent.
  assert [r["url"] for r in requests] == ["https://opencode.ai/zen/go/v1/usage", "https://opencode.ai/inference/go/v1/usage"], requests
  key, console = (r["headers"] for r in requests)
  assert key["authorization"] == "Bearer sk-FAKE-STORE-GO" and "x-opencode-org-id" not in key, key
  assert console["authorization"] == "Bearer FAKE-CONSOLE-ACCESS" and console.get("x-opencode-org-id") == "org_FAKE", console
  rolling, weekly, monthly = record["limits"]
  assert (rolling["label"], rolling["percent"], weekly["label"], weekly["percent"], monthly) == (
    "Rolling (5h)", 0.1, "Weekly (7-day)", 0.2, {"label": "Monthly", "percent": 0.3, "resetsAt": ""}), record["limits"]
  now = datetime.now(timezone.utc)
  for window, seconds in ((rolling, 3600), (weekly, 86400)):
    assert window["resetsAt"], "no reset time for " + window["label"]
    assert abs(datetime.fromisoformat(window["resetsAt"]) - (now + timedelta(seconds=seconds))) < timedelta(minutes=5), window
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False, (record["usageStatusText"], record["authHelpText"], record["limitsStale"])

  assert record["hasLocalStats"] is True, "no local stats"
  assert record["modelUsage"] == {"GLM-5": {"inputTokens": 65, "outputTokens": 45, "cacheReadInputTokens": 100, "cacheCreationInputTokens": 0}}, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"], record["totalSessions"], record["todayTotalTokens"]) == (1, 1, 1, 210), (record["todayPrompts"], record["totalPrompts"], record["totalSessions"], record["todayTotalTokens"])
