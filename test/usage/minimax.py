# SPDX-License-Identifier: GPL-3.0-only
# A machine where `mmx` is signed in to MiniMax's China region on a Token Plan,
# and opencode has spent that plan today and yesterday.

import json
import sqlite3
from datetime import datetime, timedelta, timezone

TOKEN = "sk-FAKE-MINIMAX-CN"
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


# (session, message, data). ses_a: two steps answer one prompt and a third
# answers another; ses_b was spent on yesterday's China-region plan. ses_c is
# not MiniMax's: an Anthropic run, and a gateway whose id only starts with
# "minimax".
MESSAGES = [
  ("ses_a", "msg_a1", assistant("minimax-coding-plan", "MiniMax-M2", "msg_u1", NOON, (100, 40, 10), (200, 30))),
  ("ses_a", "msg_a2", assistant("minimax-coding-plan", "MiniMax-M2", "msg_u1", NOON + timedelta(minutes=1), (50, 20, 0), (300, 0))),
  ("ses_a", "msg_a3", assistant("minimax", "MiniMax-M2", "msg_u2", NOON + timedelta(minutes=2), (10, 5, 0))),
  ("ses_b", "msg_b1", assistant("minimax-cn", "MiniMax/MiniMax-M2.1", "msg_u3", YESTERDAY, (7, 3, 0))),
  ("ses_c", "msg_c1", assistant("anthropic", "claude-sonnet", "msg_u4", NOON, (900, 900, 0))),
  ("ses_c", "msg_c2", assistant("minimax-gateway", "MiniMax-M2", "msg_u5", NOON, (800, 800, 0))),
]

# The general row is not the first usable one: an image allowance and another
# model's row come before it.
QUOTA = {
  "model_remains": [
    {"model_name": "image-01", "current_interval_total_count": 50, "current_interval_remaining_percent": 1, "current_interval_status": 1,
     "current_weekly_total_count": 350, "current_weekly_remaining_percent": 1, "current_weekly_status": 1, "end_time": 4070908800000},
    {"model_name": "MiniMax-M2", "current_interval_total_count": 1500, "current_interval_remaining_percent": 99, "current_interval_status": 1,
     "current_weekly_total_count": 9000, "current_weekly_remaining_percent": 99, "current_weekly_status": 1},
    {
      "model_name": "general",
      "current_interval_total_count": 1500, "current_interval_remaining_percent": 75, "current_interval_status": 1, "end_time": 4070908800000,
      # Spent for the week whatever the stale percentage says, and no end time:
      # the window says how long it has left instead.
      "current_weekly_total_count": 9000, "current_weekly_remaining_percent": 12.5, "current_weekly_status": 2,
      "weekly_remains_time": 3 * 86400 * 1000,
    },
  ],
  "base_resp": {"status_code": 0, "status_msg": "success"},
}

ROUTES = [("/v1/token_plan/remains", QUOTA)]


def setup(home, bin):
  mmx = home / ".mmx"
  mmx.mkdir(exist_ok=True)
  (mmx / "config.json").write_text(json.dumps({"api_key": TOKEN, "region": "cn"}))
  db = home / ".local/share/opencode/opencode.db"
  db.parent.mkdir(parents=True, exist_ok=True)
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
  assert record["ready"] is True and record["tierLabel"] == "Token Plan", (record["ready"], record["tierLabel"])
  # China-region credentials ask the China host, with the key as a bearer.
  assert [r["url"] for r in requests] == ["https://api.minimaxi.com/v1/token_plan/remains"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer " + TOKEN, "the key was not sent"
  session, weekly = record["limits"]
  assert session == {"label": "Session (5-hour)", "percent": 0.25, "resetsAt": "2099-01-01T00:00:00+00:00"}, session
  assert weekly["label"] == "Weekly (7-day)" and weekly["percent"] == 1.0, weekly
  expected_reset = datetime.now(timezone.utc) + timedelta(days=3)
  assert weekly["resetsAt"], "the weekly window has no reset time"
  assert abs(datetime.fromisoformat(weekly["resetsAt"]) - expected_reset) < timedelta(minutes=5), weekly["resetsAt"]
  assert len(record["limits"]) == 2, record["limits"]
  assert record["limitsStale"] is False and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limitsStale"], record["usageStatusText"], record["authHelpText"])
  assert record["limitsFetchedAt"] > 0, "no fetch time"

  assert record["hasLocalStats"] is True, "no local stats"
  assert record["modelUsage"] == {
    "MiniMax-M2": {"inputTokens": 160, "outputTokens": 75, "cacheReadInputTokens": 500, "cacheCreationInputTokens": 30},
    "MiniMax-M2.1": {"inputTokens": 7, "outputTokens": 3, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  # Two steps answering one prompt are one prompt.
  assert (record["todayPrompts"], record["totalPrompts"]) == (2, 3), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (1, 2), (record["todaySessions"], record["totalSessions"])
  assert record["todayTotalTokens"] == 765 and record["todayTokensByModel"] == {"MiniMax-M2": 765}, (record["todayTotalTokens"], record["todayTokensByModel"])
  days = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {days[-1]: 765, days[-2]: 10}.get(d, 0)} for d in days], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == days[-2:], record["activeDates"]
