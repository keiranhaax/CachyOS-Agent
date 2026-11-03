# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to the Devin CLI on a daily/weekly quota plan, with its
# session database (two sessions: three prompts and two models over today and
# yesterday) and two status caches, the newer from the current sign-in. Devin
# is read from local files alone, so no request goes out.

import base64
import json
import os
import sqlite3
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

NOW = int(time.time())
DAILY_RESET, WEEKLY_RESET = 4_000_000_000, 4_000_604_800  # 2096-10-02 and 2096-10-09, still ahead
OLD_FETCH, NEW_FETCH = NOW - 3 * 3600, NOW - 120


def varint(value):
  out = b""
  while True:
    byte, value = value & 0x7F, value >> 7
    out += bytes([byte | (0x80 if value else 0)])
    if not value:
      return out


def field(number, value):
  if isinstance(value, int):
    return varint(number << 3) + varint(value)
  data = value.encode() if isinstance(value, str) else value
  return varint(number << 3 | 2) + varint(len(data)) + data


def user_status(name, remaining, resets):
  """A GetUserStatus answer as the CLI caches it: the plan tier at 10 and the
  PlanStatus at 13, whose daily/weekly percent left are 14/15 and resets 17/18.
  The plan's own tier (1) and the status tier (10) are decoys: the name wins."""
  plan = field(1, 1) + field(2, name) + field(35, 2)
  # Credits used with no credit grant in the plan: a quota plan has no bucket.
  status = field(1, plan) + field(6, 10) + field(14, remaining[0]) + field(15, remaining[1]) + field(17, resets[0]) + field(18, resets[1])
  return field(10, 2) + field(13, status)


def moment(days_ago, hour):
  return (datetime.combine(date.today() - timedelta(days=days_ago), datetime.min.time()) + timedelta(hours=hour)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def reply(model, inputs, outputs, cache_read, cache_creation):
  metrics = {"input_tokens": inputs, "output_tokens": outputs, "cache_read_tokens": cache_read, "cache_creation_tokens": cache_creation}
  return json.dumps({"role": "assistant", "content": "ok", "metadata": {"generation_model": model, "metrics": metrics}})


def setup(home, bin):
  data = home / ".local" / "share" / "devin" / "cli"
  data.mkdir(parents=True)
  credentials = data.parent / "credentials.toml"
  credentials.write_text('token = "FAKE-DEVIN-TOKEN"\n')
  os.utime(credentials, (NOW - 86400, NOW - 86400))

  conn = sqlite3.connect(data / "sessions.db")
  conn.executescript(
    "CREATE TABLE message_nodes (session_id TEXT, created_at TEXT, chat_message TEXT);"
    "CREATE TABLE prompt_history (session_id TEXT, timestamp TEXT);"
  )
  conn.executemany("INSERT INTO message_nodes VALUES (?, ?, ?)", [
    ("ses-1", moment(0, 11), reply("claude-sonnet-4-5", 1200, 300, 5000, 800)),
    ("ses-1", moment(0, 12), reply("claude-sonnet-4-5", 400, 100, 2000, 0)),
    ("ses-1", moment(0, 12), json.dumps({"role": "user", "content": "refactor it"})),
    ("ses-2", moment(1, 12), reply("swe-1-5", 700, 90, 0, 0)),
    # A row Devin never dated is unreadable, not today's.
    ("ses-3", None, reply("claude-sonnet-4-5", 9_999_999, 9_999_999, 0, 0)),
  ])
  conn.executemany("INSERT INTO prompt_history VALUES (?, ?)", [
    ("ses-1", moment(0, 10)), ("ses-1", moment(0, 11)), ("ses-1", moment(0, 12)), ("ses-2", moment(1, 11)),
  ])
  conn.commit()
  conn.close()

  cache = Path(os.environ["XDG_CACHE_HOME"]) / "devin" / "cli"
  cache.mkdir(parents=True)
  for name, fetched, payload in (
    ("user_status.0a1b.bin", OLD_FETCH, user_status("Devin Free", (10, 20), (DAILY_RESET + 86400, WEEKLY_RESET))),
    ("user_status.7c2d.bin", NEW_FETCH, user_status("Devin Pro", (70, 45), (DAILY_RESET, WEEKLY_RESET))),
  ):
    (cache / name).write_text(json.dumps({"payload": base64.b64encode(payload).decode(), "fetched_at_secs": fetched}))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])

  # The newest cache, under the plan's own name; a percent is what is left, reported as spent.
  assert record["tierLabel"] == "Devin Pro", record["tierLabel"]
  assert record["limits"] == [
    {"label": "Daily", "percent": 0.3, "resetsAt": "2096-10-02T07:06:40+00:00"},
    {"label": "Weekly", "percent": 0.55, "resetsAt": "2096-10-09T07:06:40+00:00"},
  ], record["limits"]
  assert record["limitsFetchedAt"] == NEW_FETCH * 1000 and record["limitsStale"] is False, (record["limitsFetchedAt"], record["limitsStale"])

  today, yesterday = date.today(), date.today() - timedelta(days=1)
  assert record["todayPrompts"] == 3 and record["totalPrompts"] == 4, (record["todayPrompts"], record["totalPrompts"])
  assert record["todaySessions"] == 1 and record["totalSessions"] == 2, (record["todaySessions"], record["totalSessions"])
  assert record["modelUsage"] == {
    "claude-sonnet-4-5": {"inputTokens": 1600, "outputTokens": 400, "cacheReadInputTokens": 7000, "cacheCreationInputTokens": 800},
    "swe-1-5": {"inputTokens": 700, "outputTokens": 90, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 9800 and record["todayTokensByModel"] == {"claude-sonnet-4-5": 9800}, (record["todayTotalTokens"], record["todayTokensByModel"])
  tokens = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert tokens[today.isoformat()] == 9800 and tokens[yesterday.isoformat()] == 790 and sum(tokens.values()) == 10590, tokens
  assert record["activeDays"] == 2 and record["activeDates"] == [yesterday.isoformat(), today.isoformat()], (record["activeDays"], record["activeDates"])
