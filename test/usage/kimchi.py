# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Kimchi's EU gateway (key and region saved by its
# login) on the Teams plan, with credits left and a personal and a team
# budget on one monthly period, one capped per provider. An opencode database
# holds replies on Kimchi's routes, and one on another provider whose id only
# starts with kimchi.

import json
import sqlite3
from datetime import date, datetime, time, timedelta


def local_ms(days_ago, hour):
  return int(datetime.combine(date.today() - timedelta(days=days_ago), time(hour)).timestamp() * 1000)


def reply(provider, model, parent, created, input_tokens, output_tokens, cache_read=0):
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent, "time": {"created": created},
    "tokens": {"input": input_tokens, "output": output_tokens, "reasoning": 0, "cache": {"read": cache_read, "write": 0}},
  })


def setup(home, bin):
  config = home / ".config" / "kimchi"
  config.mkdir(parents=True, exist_ok=True)
  (config / "config.json").write_text(json.dumps({"apiKey": "kimchi-FAKE-KEY", "region": "eu"}))
  db_path = home / ".local" / "share" / "opencode" / "opencode.db"
  db_path.parent.mkdir(parents=True, exist_ok=True)
  db_path.unlink(missing_ok=True)
  db = sqlite3.connect(db_path)
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  db.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [
    ("m1", "s1", reply("kimchi", "kimi-k2.5", "u1", local_ms(0, 10), 800, 150)),
    ("m2", "s1", reply("kimchi-dev", "kimi-k2.5", "u2", local_ms(0, 11), 400, 50, cache_read=100)),
    ("m3", "s2", reply("kimchi-dev/anthropic", "claude-sonnet-4", "u3", local_ms(1, 15), 300, 60)),
    ("m4", "s2", reply("kimchi-other", "elsewhere", "u4", local_ms(0, 12), 9999, 9999)),
  ])
  db.commit()
  db.close()


PERIOD = {"startTime": "2026-11-01T00:00:00Z", "endTime": "2026-12-01T00:00:00Z"}

ROUTES = [
  ("/v1/credits", {"serverless": True, "tier": "team", "remaining": "12.50", "has_credits": True}),
  ("/v1/budget", {
    "period": PERIOD,
    "budgets": [
      {
        "scope": "USER", "budgetLimitUsd": "100.00", "totalSpendUsd": "37.25",
        "providerBudgets": [
          {"provider": "anthropic", "limitType": "CAPPED", "budgetLimitUsd": "40.00", "usageUsd": "10.00"},
          {"provider": "openai", "limitType": "UNLIMITED", "budgetLimitUsd": "500.00", "usageUsd": "5.00"},
        ],
      },
      {"scope": "TEAM_POOLED", "budgetLimitUsd": "2000.00", "totalSpendUsd": "500.00", "providerBudgets": []},
    ],
  }),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Teams", record["tierLabel"]
  assert record.get("balance") == {"remaining": 12.5, "funded": 0, "spent": 0, "currency": "USD", "estimated": False}, record.get("balance")
  # Two budgets share the period, so each is titled by its scope; the uncapped provider has no line.
  end = PERIOD["endTime"]
  assert record["limits"] == [
    {"label": "Budget", "title": "Budget Monthly", "percent": 0.3725, "resetsAt": end},
    {"label": "Anthropic budget", "title": "Anthropic budget (Budget)", "percent": 0.25, "resetsAt": end},
    {"label": "Team pool", "title": "Team pool Monthly", "percent": 0.25, "resetsAt": end},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert abs(record["limitsFetchedAt"] / 1000 - datetime.now().timestamp()) < 120, record["limitsFetchedAt"]

  yesterday, today = (date.today() - timedelta(days=1)).isoformat(), date.today().isoformat()
  assert record["hasLocalStats"] is True and record["totalPrompts"] == 3 and record["totalSessions"] == 2, record["totalPrompts"]
  assert record["todayPrompts"] == 2 and record["todaySessions"] == 1 and record["todayTotalTokens"] == 1500, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"kimi-k2.5": 1500}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "kimi-k2.5": {"inputTokens": 1200, "outputTokens": 200, "cacheReadInputTokens": 100, "cacheCreationInputTokens": 0},
    "claude-sonnet-4": {"inputTokens": 300, "outputTokens": 60, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": yesterday, "messageCount": 360}, {"date": today, "messageCount": 1500}], record["recentDays"]

  assert [r["url"] for r in requests] == ["https://llm.eu.kimchi.dev/v1/credits", "https://llm.eu.kimchi.dev/v1/budget"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer kimchi-FAKE-KEY" for r in requests), "the key was not sent on every request"
