# SPDX-License-Identifier: GPL-3.0-only
# A machine where pi is signed in to Ollama Cloud, on a plan with monthly
# included credits and some bought ones, and opencode has run cloud models
# today and yesterday, through Ollama Cloud and through the local daemon.

import json
import sqlite3
from datetime import datetime, timedelta

TOKEN = "sk-FAKE-OLLAMA-PI"
NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)
YESTERDAY = NOON - timedelta(days=1)
DAY = "%Y-%m-%d"


def ms(moment):
  return int(moment.timestamp() * 1000)


def assistant(provider, model, parent, moment, tokens, cache=(0, 0)):
  # An opencode message row as the original `message` table keeps it.
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent,
    "time": {"created": ms(moment)},
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": 0, "cache": {"read": cache[0], "write": cache[1]}},
  })


# A cloud-tagged model through the local daemon is Ollama's too; a local one
# is not. Two releases of one model are one model.
MESSAGES = [
  ("ses_a", "msg_a1", assistant("ollama-cloud", "deepseek-v4-pro:0813", "msg_u1", NOON, (100, 50), (20, 0))),
  ("ses_a", "msg_a2", assistant("ollama", "gpt-oss:120b-cloud", "msg_u2", NOON + timedelta(minutes=1), (30, 10))),
  ("ses_a", "msg_a3", assistant("ollama", "llama3.2:3b", "msg_u3", NOON + timedelta(minutes=2), (500, 500))),
  ("ses_b", "msg_b1", assistant("ollama-cloud", "deepseek-v4-pro:0912", "msg_u4", YESTERDAY, (5, 5))),
]

ROUTES = [
  ("/api/balance", {
    "included": {"balance_usd": 12.5, "allowance_usd": 50.0, "period": {"until": "2099-02-01T00:00:00Z"}},
    "purchased": {"balance_usd": 8.25},
  }),
  ("/api/me", {"name": "fixture", "plan": "pro"}),
]


def setup(home, bin):
  pi = home / ".pi/agent"
  pi.mkdir(parents=True, exist_ok=True)
  (pi / "auth.json").write_text(json.dumps({"ollama-cloud": {"type": "api_key", "key": TOKEN}}))
  db = home / ".local/share/opencode/opencode.db"
  db.parent.mkdir(parents=True, exist_ok=True)
  db.unlink(missing_ok=True)
  conn = sqlite3.connect(db)
  with conn:
    conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER NOT NULL, parent_id TEXT)")
    conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
    for session in ("ses_a", "ses_b"):
      conn.execute("INSERT INTO session VALUES (?, ?, NULL)", (session, ms(YESTERDAY - timedelta(hours=1))))
    conn.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [(message, session, data) for session, message, data in MESSAGES])
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  # The balance is asked first, then the plan, which is a POST.
  assert [(r["method"], r["url"]) for r in requests] == [("GET", "https://ollama.com/api/balance"), ("POST", "https://ollama.com/api/me")], requests
  assert all(r["headers"]["authorization"] == "Bearer " + TOKEN for r in requests), "the key was not sent"
  # 12.5 of 50 left is 75% used; the bought credits are only a balance.
  assert record["limits"] == [{"label": "Included credits", "title": "Monthly", "percent": 0.75, "resetsAt": "2099-02-01T00:00:00Z"}], record["limits"]
  assert record.get("balance") == {"remaining": 8.25, "funded": 0, "spent": 0, "currency": "USD", "estimated": False}, record.get("balance")
  assert record["limitsStale"] is False and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limitsStale"], record["usageStatusText"], record["authHelpText"])
  assert record["limitsFetchedAt"] > 0, "no fetch time"

  assert record["hasLocalStats"] is True, "no local stats"
  assert record["modelUsage"] == {
    "deepseek-v4-pro": {"inputTokens": 105, "outputTokens": 55, "cacheReadInputTokens": 20, "cacheCreationInputTokens": 0},
    "gpt-oss": {"inputTokens": 30, "outputTokens": 10, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"]) == (2, 3), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (1, 2), (record["todaySessions"], record["totalSessions"])
  assert record["todayTotalTokens"] == 210 and record["todayTokensByModel"] == {"deepseek-v4-pro": 170, "gpt-oss": 40}, (record["todayTotalTokens"], record["todayTokensByModel"])
  days = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {days[-1]: 210, days[-2]: 10}.get(d, 0)} for d in days], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == days[-2:], record["activeDates"]
