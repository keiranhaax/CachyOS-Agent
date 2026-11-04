# SPDX-License-Identifier: GPL-3.0-only
# A machine where Claude Code is sent to Z.ai's Anthropic-compatible API by its
# settings.json, and is not signed in to Anthropic. Its stats-cache.json and
# history.jsonl say nothing of who answered, so while it is sent there none of
# it is Anthropic's, and Claude counts nothing.

import json
from datetime import datetime, time as clock

TODAY = datetime.combine(datetime.now().date(), clock.min)


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / "settings.json").write_text(json.dumps({"env": {"ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic"}}))
  today = TODAY.strftime("%Y-%m-%d")
  (claude / "stats-cache.json").write_text(json.dumps({
    "totalSessions": 6,
    "totalMessages": 40,
    "dailyActivity": [{"date": today, "messageCount": 12}],
    "dailyModelTokens": [{"date": today, "tokensByModel": {"claude-sonnet-4-5": 1000}}],
    "modelUsage": {"claude-sonnet-4-5": {"inputTokens": 700, "outputTokens": 300}},
  }))
  (claude / "history.jsonl").write_text(json.dumps({"display": "fix the failing test", "timestamp": int(TODAY.timestamp() * 1000) + 60_000, "sessionId": "s1"}) + "\n")


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is False and record["usageStatusText"] == "Waiting for auth", (record["ready"], record["usageStatusText"])
  assert (record["todayPrompts"], record["todaySessions"], record["totalPrompts"], record["totalSessions"]) == (0, 0, 0, 0), record["totalPrompts"]
  assert record["todayTotalTokens"] == 0 and record["todayTokensByModel"] == {} and record["modelUsage"] == {}, record["modelUsage"]
  assert record["activeDays"] == 0 and record["activeDates"] == [] and all(d["messageCount"] == 0 for d in record["recentDays"]), record["activeDates"]
