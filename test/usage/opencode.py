# SPDX-License-Identifier: GPL-3.0-only
# A machine where opencode is signed in to the Go plan with a key in its
# auth.json, beside a custom gateway's key that must stay home, and has spent
# the Zen and Go providers today and yesterday.

import json
import sqlite3
from datetime import datetime, timedelta

TOKEN = "sk-FAKE-OPENCODE-GO"
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
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": tokens[2], "cache": {"read": cache[0], "write": cache[1]}},
  })


# Both subscription providers count, whatever the model's own prefix or
# variant; a gateway named like them and Anthropic's do not. Thinking tokens
# are part of what was generated.
MESSAGES = [
  ("ses_a", "msg_a1", assistant("opencode-go", "glm-5", "msg_u1", NOON, (100, 50, 25), (10, 5))),
  ("ses_a", "msg_a2", assistant("opencode", "kimi-k2:high", "msg_u2", NOON + timedelta(minutes=1), (20, 10, 0))),
  ("ses_b", "msg_b1", assistant("opencode-go", "zen/glm-5", "msg_u3", YESTERDAY, (4, 6, 0))),
  ("ses_c", "msg_c1", assistant("opencode-local", "qwen3", "msg_u4", NOON, (700, 700, 0))),
  ("ses_c", "msg_c2", assistant("anthropic", "claude-sonnet", "msg_u5", NOON, (800, 800, 0))),
]

ROUTES = [("/zen/go/v1/usage", {"usage": {
  "rolling": {"percent": 25, "resetsAt": "2099-01-01T05:00:00Z", "status": "ok"},
  "weekly": {"percent": 62.5, "resetsAt": "2099-01-05T00:00:00Z"},
  # Spent until it resets, whatever the percentage reads.
  "monthly": {"percent": 40, "resetsAt": "2099-02-01T00:00:00Z", "status": "rate-limited"},
}})]


def setup(home, bin):
  data = home / ".local/share/opencode"
  data.mkdir(parents=True, exist_ok=True)
  (data / "auth.json").write_text(json.dumps({
    "opencode-local": {"type": "api", "key": "sk-FAKE-GATEWAY"},
    "opencode-go": {"type": "api", "key": TOKEN},
  }))
  db = data / "opencode.db"
  db.unlink(missing_ok=True)
  conn = sqlite3.connect(db)
  with conn:
    conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER NOT NULL, parent_id TEXT)")
    conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
    for session in ("ses_a", "ses_b", "ses_c"):
      conn.execute("INSERT INTO session VALUES (?, ?, NULL)", (session, ms(YESTERDAY - timedelta(hours=1))))
    conn.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [(message, session, data) for session, message, data in MESSAGES])
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Go", (record["ready"], record["tierLabel"])
  # One request: the gateway's key is never tried.
  assert [r["url"] for r in requests] == ["https://opencode.ai/zen/go/v1/usage"], requests
  headers = requests[0]["headers"]
  assert headers["authorization"] == "Bearer " + TOKEN, "the key was not sent"
  assert headers["user-agent"] == "cachyos-agent-usage-opencode/1.0" and "x-opencode-org-id" not in headers, headers
  assert record["limits"] == [
    {"label": "Rolling (5h)", "percent": 0.25, "resetsAt": "2099-01-01T05:00:00Z"},
    {"label": "Weekly (7-day)", "percent": 0.625, "resetsAt": "2099-01-05T00:00:00Z"},
    {"label": "Monthly", "percent": 1.0, "resetsAt": "2099-02-01T00:00:00Z"},
  ], record["limits"]
  assert record["limitsStale"] is False and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limitsStale"], record["usageStatusText"], record["authHelpText"])
  assert record["limitsFetchedAt"] > 0, "no fetch time"

  assert record["hasLocalStats"] is True, "no local stats"
  assert record["modelUsage"] == {
    "GLM-5": {"inputTokens": 104, "outputTokens": 81, "cacheReadInputTokens": 10, "cacheCreationInputTokens": 5},
    "kimi-k2": {"inputTokens": 20, "outputTokens": 10, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"]) == (2, 3), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (1, 2), (record["todaySessions"], record["totalSessions"])
  assert record["todayTotalTokens"] == 220 and record["todayTokensByModel"] == {"GLM-5": 190, "kimi-k2": 30}, (record["todayTotalTokens"], record["todayTokensByModel"])
  days = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {days[-1]: 220, days[-2]: 10}.get(d, 0)} for d in days], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == days[-2:], record["activeDates"]
