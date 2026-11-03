# SPDX-License-Identifier: GPL-3.0-only
# A machine with an OpenRouter inference key in the environment: the key has a
# monthly credit limit and the account has a balance. An opencode database
# holds replies on two OpenRouter models over two days, and one on another
# provider.

import json
import sqlite3
from datetime import date, datetime, time, timedelta

ENV = {"OPENROUTER_API_KEY": "sk-or-FAKE-INFERENCE"}


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
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  db.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [
    ("m1", "s1", reply("openrouter", "anthropic/claude-sonnet-4", "u1", local_ms(0, 10), 1200, 300, reasoning=100, cache_read=200, cache_write=50)),
    ("m2", "s1", reply("openrouter", "openai/gpt-5", "u2", local_ms(0, 11), 600, 100)),
    ("m3", "s2", reply("synthetic", "hf:zai-org/GLM-4.6", "u3", local_ms(0, 12), 9999, 9999)),
    ("m4", "s2", reply("openrouter", "anthropic/claude-sonnet-4", "u4", local_ms(1, 15), 500, 50)),
  ])
  db.commit()
  db.close()


ROUTES = [
  ("/api/v1/key", {"data": {"label": "sk-or-v1-abc...xyz", "limit": 50, "limit_remaining": 12.5, "limit_reset": "monthly", "usage": 37.5, "is_management_key": False}}),
  ("/api/v1/credits", {"data": {"total_credits": 100.5, "total_usage": 42.25}}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid" and record["hasPromptStats"] is True
  # The limit starts over monthly, which names the meter; it has no reset time.
  assert record["limits"] == [{"label": "Monthly key limit", "title": "Monthly key limit", "percent": 0.75, "resetsAt": ""}], record["limits"]
  assert record.get("balance") == {"remaining": 58.25, "funded": 100.5, "spent": 42.25, "currency": "USD", "estimated": False}, record.get("balance")
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert abs(record["limitsFetchedAt"] / 1000 - datetime.now().timestamp()) < 120, record["limitsFetchedAt"]

  yesterday, today = (date.today() - timedelta(days=1)).isoformat(), date.today().isoformat()
  assert "scope" not in record, "local stats are this machine's, not the account's"
  assert record["hasLocalStats"] is True and record["totalPrompts"] == 3 and record["totalSessions"] == 2, record["totalPrompts"]
  assert record["todayPrompts"] == 2 and record["todaySessions"] == 1 and record["todayTotalTokens"] == 2550, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"claude-sonnet-4": 1850, "gpt-5": 700}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "claude-sonnet-4": {"inputTokens": 1700, "outputTokens": 450, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 50},
    "gpt-5": {"inputTokens": 600, "outputTokens": 100, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": yesterday, "messageCount": 550}, {"date": today, "messageCount": 2550}], record["recentDays"]

  assert [r["url"] for r in requests] == ["https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer sk-or-FAKE-INFERENCE" for r in requests), "the key was not sent on every request"
