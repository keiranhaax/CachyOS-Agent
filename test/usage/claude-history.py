# SPDX-License-Identifier: GPL-3.0-only
# A machine where Claude Code has run but kept neither transcripts nor a
# stats-cache.json: only the prompts typed today in history.jsonl, one a
# built-in command that asks the model nothing.

import json
from datetime import datetime, time as clock, timedelta

TODAY = datetime.combine(datetime.now().date(), clock.min)


def ms(moment):
  return int(moment.timestamp() * 1000)


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  entries = [
    {"display": "yesterday's prompt", "timestamp": ms(TODAY - timedelta(hours=3)), "sessionId": "s0"},
    {"display": "fix the failing test", "timestamp": ms(TODAY + timedelta(minutes=1)), "sessionId": "s1"},
    {"display": "/compact", "timestamp": ms(TODAY + timedelta(minutes=2)), "sessionId": "s2"},
    {"display": "and the other one", "timestamp": ms(TODAY + timedelta(minutes=3)), "sessionId": "s1"},
  ]
  (claude / "history.jsonl").write_text("".join(json.dumps(entry) + "\n" for entry in entries))


def check(record, requests):
  assert requests == [], requests
  assert record["usageStatusText"] == "Waiting for auth" and record["limits"] == [], (record["usageStatusText"], record["limits"])
  assert (record["todayPrompts"], record["todaySessions"]) == (2, 1), (record["todayPrompts"], record["todaySessions"])
  # Nothing here is tokens or a lifetime count.
  assert record["totalPrompts"] == 0 and record["modelUsage"] == {} and record["todayTotalTokens"] == 0, record["modelUsage"]
