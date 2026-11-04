# SPDX-License-Identifier: GPL-3.0-only
# A machine where Claude Code kept no transcripts (only a stats-cache.json that
# counts one day of Sonnet), and opencode has spent the same subscription today
# and yesterday through its anthropic provider, beside a gateway named like it
# and another provider's models, which are not Claude's.

import json
import sqlite3
from datetime import datetime, timedelta

NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)
YESTERDAY = NOON - timedelta(days=1)
DAY = "%Y-%m-%d"


def ms(moment):
  return int(moment.timestamp() * 1000)


def assistant(provider, model, parent, moment, tokens, cache=(0, 0), **extra):
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent,
    "time": {"created": ms(moment)},
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": tokens[2], "cache": {"read": cache[0], "write": cache[1]}},
    **extra,
  })


# Thinking tokens are generated tokens, so they count as output; a model id
# may carry the provider's prefix. The scan's first filter is loose, so a
# gateway's row that names "anthropic" elsewhere still has to be refused.
MESSAGES = [
  ("ses_a", "msg_a1", assistant("anthropic", "claude-sonnet-4-5", "msg_u1", NOON, (100, 50, 25), (10, 5))),
  ("ses_b", "msg_b1", assistant("anthropic", "anthropic/claude-opus-4-1", "msg_u2", YESTERDAY, (4, 6, 0))),
  ("ses_c", "msg_c1", assistant("anthropic-proxy", "claude-sonnet-4-5", "msg_u3", NOON, (700, 700, 0), agent="anthropic")),
  ("ses_c", "msg_c2", assistant("opencode-go", "glm-5", "msg_u4", NOON, (800, 800, 0))),
]


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / "stats-cache.json").write_text(json.dumps({
    "totalSessions": 6,
    "totalMessages": 40,
    "dailyActivity": [{"date": NOON.strftime(DAY), "messageCount": 12}],
    "dailyModelTokens": [{"date": NOON.strftime(DAY), "tokensByModel": {"claude-sonnet-4-5": 1000}}],
    "modelUsage": {"claude-sonnet-4-5": {"inputTokens": 700, "outputTokens": 300, "cacheReadInputTokens": 5000, "cacheCreationInputTokens": 400}},
  }))
  data = home / ".local/share/opencode"
  data.mkdir(parents=True, exist_ok=True)
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
  assert requests == [], requests
  assert record["ready"] is True and record["usageStatusText"] == "Waiting for auth", (record["ready"], record["usageStatusText"])
  # The cache's counters and opencode's replies are added together.
  assert (record["todayPrompts"], record["todaySessions"]) == (1, 1), (record["todayPrompts"], record["todaySessions"])
  assert (record["totalPrompts"], record["totalSessions"]) == (42, 8), (record["totalPrompts"], record["totalSessions"])
  assert record["todayTotalTokens"] == 1190 and record["todayTokensByModel"] == {"claude-sonnet-4-5": 1190}, record["todayTokensByModel"]
  week = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {week[6]: 1190, week[5]: 10}.get(d, 0)} for d in week], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == [week[5], week[6]], record["activeDates"]
  assert record["modelUsage"] == {
    "claude-sonnet-4-5": {"inputTokens": 800, "outputTokens": 375, "cacheReadInputTokens": 5010, "cacheCreationInputTokens": 405},
    "claude-opus-4-1": {"inputTokens": 4, "outputTokens": 6, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
