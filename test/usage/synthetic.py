# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Synthetic key in the environment, whose quotas answer, and
# an opencode database with replies on Synthetic's models (two answering one
# prompt, one on another day, and one on OpenRouter that is not Synthetic's).

import json
import sqlite3
from datetime import date, datetime, time, timedelta

ENV = {"SYNTHETIC_API_KEY": "sk-FAKE-SYNTHETIC"}


def local_ms(days_ago, hour):
  return int(datetime.combine(date.today() - timedelta(days=days_ago), time(hour)).timestamp() * 1000)


def reply(provider, model, parent, created, input_tokens, output_tokens, reasoning=0, cache_read=0, cache_write=0):
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent, "time": {"created": created},
    "tokens": {"input": input_tokens, "output": output_tokens, "reasoning": reasoning, "cache": {"read": cache_read, "write": cache_write}},
  })


def setup(home, bin):
  db_path = home / ".local" / "share" / "opencode" / "opencode.db"
  db_path.parent.mkdir(parents=True, exist_ok=True)
  db_path.unlink(missing_ok=True)
  db = sqlite3.connect(db_path)
  db.execute("CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER)")
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  db.executemany("INSERT INTO session VALUES (?, NULL, ?)", [("s1", local_ms(5, 9)), ("s2", local_ms(5, 9))])
  db.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [
    ("m1", "s1", reply("synthetic", "hf:zai-org/GLM-4.6", "u1", local_ms(0, 10), 1000, 200, reasoning=50, cache_read=300, cache_write=40)),
    ("m2", "s1", reply("synthetic", "hf:zai-org/GLM-4.6", "u1", local_ms(0, 11), 500, 100)),
    ("m3", "s2", reply("synthetic", "hf:MiniMaxAI/MiniMax-M2", "u2", local_ms(1, 15), 2000, 400)),
    ("m4", "s2", reply("openrouter", "anthropic/claude-sonnet-4", "u3", local_ms(0, 12), 9999, 9999)),
  ])
  db.commit()
  db.close()


ROUTES = [("/v2/quotas", {
  "subscription": {"limit": 0, "requests": 0, "renewsAt": "2026-12-01T00:00:00.000Z"},
  "search": {"hourly": {"limit": 250, "requests": 3, "renewsAt": "2026-12-01T10:00:00.000Z"}},
  "freeToolCalls": {"limit": 100, "requests": 10, "renewsAt": "2026-12-02T00:00:00.000Z"},
  "weeklyTokenLimit": {"nextRegenAt": "2026-12-01T00:30:00.000Z", "percentRemaining": 62.5},
  "rollingFiveHourLimit": {"nextTickAt": "2026-12-01T00:05:00.000Z", "remaining": 150, "max": 600, "limited": False},
})]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "" and record["usageStatusText"] == "" and record["authHelpText"] == ""
  # The subscription bucket stands in only when neither the rolling nor the weekly limit parsed.
  assert record["limits"] == [
    {"label": "Rolling (5h)", "percent": 0.75, "resetsAt": ""},
    {"label": "Weekly credits", "percent": 0.375, "resetsAt": ""},
    {"label": "Search (hourly)", "title": "Search", "percent": 0.012, "resetsAt": "2026-12-01T10:00:00.000Z"},
    {"label": "Free tool calls", "percent": 0.1, "resetsAt": "2026-12-02T00:00:00.000Z"},
  ], record["limits"]
  assert record["limitsStale"] is False and abs(record["limitsFetchedAt"] / 1000 - datetime.now().timestamp()) < 120

  yesterday, today = (date.today() - timedelta(days=1)).isoformat(), date.today().isoformat()
  assert record["hasLocalStats"] is True and record["totalPrompts"] == 2 and record["totalSessions"] == 2, record["totalPrompts"]
  assert record["todayPrompts"] == 1 and record["todaySessions"] == 1 and record["todayTotalTokens"] == 2190, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"GLM-4.6": 2190}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "GLM-4.6": {"inputTokens": 1500, "outputTokens": 350, "cacheReadInputTokens": 300, "cacheCreationInputTokens": 40},
    "MiniMax-M2": {"inputTokens": 2000, "outputTokens": 400, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": yesterday, "messageCount": 2400}, {"date": today, "messageCount": 2190}], record["recentDays"]
  assert record["activeDates"] == [yesterday, today]

  assert [r["url"] for r in requests] == ["https://api.synthetic.new/v2/quotas"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer sk-FAKE-SYNTHETIC", "the key was not sent"
