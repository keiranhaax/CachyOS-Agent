# SPDX-License-Identifier: GPL-3.0-only
# A machine with the key in cachyos-agent's own ollama.json, which also limits
# the local stats to one model family, on a legacy plan whose limits are a
# 5-hour and a 7-day window; the plan comes back with a capitalised field.

import json
import sqlite3
from datetime import datetime, timedelta

TOKEN = "sk-FAKE-OLLAMA-CFG"
NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)


def ms(moment):
  return int(moment.timestamp() * 1000)


def assistant(model, parent, moment, tokens):
  # An opencode message row as the original `message` table keeps it.
  return json.dumps({
    "role": "assistant", "providerID": "ollama-cloud", "modelID": model, "parentID": parent,
    "time": {"created": ms(moment)},
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": 0, "cache": {"read": 0, "write": 0}},
  })


MESSAGES = [
  ("ses_a", "msg_a1", assistant("gpt-oss:120b", "msg_u1", NOON, (40, 15))),
  ("ses_a", "msg_a2", assistant("glm-4.6", "msg_u2", NOON + timedelta(minutes=1), (900, 900))),
]

ROUTES = [
  ("/api/balance", {"included": {
    "session": {"remaining_percent": 75, "resets_at": "2099-01-01T05:00:00Z"},
    "weekly": {"remaining_percent": 37.5, "resets_at": "2099-01-05T00:00:00Z"},
  }}),
  ("/api/me", {"Plan": "free"}),
]


def setup(home, bin):
  config = home / ".config/cachyos-agent"
  config.mkdir(parents=True, exist_ok=True)
  # The prefix is matched in lower case.
  (config / "ollama.json").write_text(json.dumps({"apiKey": TOKEN, "modelPrefix": "GPT"}))
  db = home / ".local/share/opencode/opencode.db"
  db.parent.mkdir(parents=True, exist_ok=True)
  db.unlink(missing_ok=True)
  conn = sqlite3.connect(db)
  with conn:
    conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER NOT NULL, parent_id TEXT)")
    conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
    conn.execute("INSERT INTO session VALUES ('ses_a', ?, NULL)", (ms(NOON - timedelta(hours=1)),))
    conn.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [(message, session, data) for session, message, data in MESSAGES])
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Free", (record["ready"], record["tierLabel"])
  assert [(r["method"], r["url"]) for r in requests] == [("GET", "https://ollama.com/api/balance"), ("POST", "https://ollama.com/api/me")], requests
  assert all(r["headers"]["authorization"] == "Bearer " + TOKEN for r in requests), "the key was not sent"
  # remaining_percent says what is left: 75% left is 0.25 used.
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.25, "resetsAt": "2099-01-01T05:00:00Z"},
    {"label": "Weekly (7-day)", "percent": 0.625, "resetsAt": "2099-01-05T00:00:00Z"},
  ], record["limits"]
  assert "balance" not in record, "a balance with no purchased credits"
  assert record["limitsStale"] is False and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limitsStale"], record["usageStatusText"], record["authHelpText"])

  # Only the gpt family counts; the glm reply is left out.
  assert record["modelUsage"] == {"gpt-oss": {"inputTokens": 40, "outputTokens": 15, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"], record["todayTotalTokens"]) == (1, 1, 55), (record["todayPrompts"], record["totalPrompts"], record["todayTotalTokens"])
