# SPDX-License-Identifier: GPL-3.0-only
# A machine where Claude Code has run but kept no transcripts and is not signed
# in: only its stats-cache.json (counters by day and model, one of them for a
# Z.ai model that went through Claude Code) and the prompts typed today in
# history.jsonl, some of which were built-in commands that ask the model nothing.

import json
from datetime import datetime, time as clock, timedelta

TODAY = datetime.combine(datetime.now().date(), clock.min)
DAY = "%Y-%m-%d"


def ms(moment):
  return int(moment.timestamp() * 1000)


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  today, two_days_ago, five_days_ago = (TODAY - timedelta(days=n) for n in (0, 2, 5))
  (claude / "stats-cache.json").write_text(json.dumps({
    "version": 2,
    "totalSessions": 6,
    "totalMessages": 40,
    "dailyActivity": [
      {"date": today.strftime(DAY), "messageCount": 12, "sessionCount": 2, "toolCallCount": 30},
      {"date": two_days_ago.strftime(DAY), "messageCount": 3, "sessionCount": 1, "toolCallCount": 4},
      {"date": five_days_ago.strftime(DAY), "messageCount": 0, "sessionCount": 0, "toolCallCount": 0},
    ],
    "dailyModelTokens": [
      # glm-4.6 is Z.ai's and a model with no tokens is no model; a repeated day keeps its first entry.
      {"date": today.strftime(DAY), "tokensByModel": {"claude-sonnet-4-5": 1000, "glm-4.6": 500, "claude-haiku-4-5": 0}},
      {"date": today.strftime(DAY), "tokensByModel": {"claude-sonnet-4-5": 9999}},
      {"date": two_days_ago.strftime(DAY), "tokensByModel": {"claude-opus-4-1": 300}},
    ],
    "modelUsage": {
      "claude-sonnet-4-5": {
        "inputTokens": 700, "outputTokens": 300, "cacheReadInputTokens": 5000, "cacheCreationInputTokens": 400,
        "webSearchRequests": 2, "costUSD": 1.2,
      },
      "claude-opus-4-1": {"inputTokens": 100, "outputTokens": 50},
      "glm-4.6": {"inputTokens": 40, "outputTokens": 10},
      "claude-broken": "not a bucket",
    },
  }))
  history = [
    {"display": "an older prompt", "timestamp": ms(TODAY - timedelta(hours=3)), "sessionId": "s0"},
    {"display": "fix the failing test", "timestamp": ms(TODAY + timedelta(minutes=1)), "sessionId": "s1"},
    {"display": "/model opus", "timestamp": ms(TODAY + timedelta(minutes=2)), "sessionId": "s1"},
    {"display": "  /usage --details", "timestamp": ms(TODAY + timedelta(minutes=3)), "sessionId": "s1"},
    {"display": "/init", "timestamp": ms(TODAY + timedelta(minutes=4)), "sessionId": "s2"},
    {"display": "/my-skill and some arguments", "timestamp": ms(TODAY + timedelta(minutes=5)), "sessionId": "s1"},
  ]
  lines = [json.dumps(entry) for entry in history]
  # A line that is not JSON, or not an object, is a bad row and not the end of the file.
  lines[2:2] = ["not json", "[1, 2]"]
  (claude / "history.jsonl").write_text("".join(line + "\n" for line in lines))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["usageStatusText"] == "Waiting for auth" and record["limits"] == [] and record["tierLabel"] == "", (record["usageStatusText"], record["tierLabel"])

  # Today's prompts are the typed ones: a command that runs on its own, with or
  # without arguments, is not, and what a prompt built-in or a skill sends is.
  assert (record["todayPrompts"], record["todaySessions"]) == (3, 2), (record["todayPrompts"], record["todaySessions"])
  assert (record["totalPrompts"], record["totalSessions"]) == (40, 6), (record["totalPrompts"], record["totalSessions"])
  assert record["todayTotalTokens"] == 1000 and record["todayTokensByModel"] == {"claude-sonnet-4-5": 1000}, record["todayTokensByModel"]
  week = [(TODAY - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {week[6]: 1000, week[4]: 300}.get(d, 0)} for d in week], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == [week[4], week[6]], record["activeDates"]
  assert record["modelUsage"] == {
    "claude-sonnet-4-5": {"inputTokens": 700, "outputTokens": 300, "cacheReadInputTokens": 5000, "cacheCreationInputTokens": 400},
    "claude-opus-4-1": {"inputTokens": 100, "outputTokens": 50, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
