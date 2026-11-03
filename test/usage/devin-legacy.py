# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Devin CLI is an older build, never signed in: lifetime
# totals per session in cli_sessions.db (no split by kind, no status cache),
# one session spanning yesterday and today and one with no model or last
# activity from two days ago.

import sqlite3
from datetime import date, datetime, time, timedelta


def at(days_ago, hour):
  return int(datetime.combine(date.today() - timedelta(days=days_ago), time(hour)).timestamp())


def setup(home, bin):
  root = home / ".local" / "share" / "devin"
  root.mkdir(parents=True)
  conn = sqlite3.connect(root / "cli_sessions.db")
  conn.executescript(
    "CREATE TABLE sessions (id TEXT, model TEXT, created_at INTEGER, last_activity_at INTEGER, total_tokens INTEGER);"
    "CREATE TABLE messages (session_id TEXT, role TEXT, timestamp INTEGER);"
  )
  conn.executemany("INSERT INTO sessions VALUES (?, ?, ?, ?, ?)", [
    # Booked on the day it was last active, not the day it began.
    ("old-1", "claude-sonnet-4-5", at(1, 9), at(0, 12), 12000),
    ("old-2", "", at(2, 9), None, 3000),
  ])
  conn.executemany("INSERT INTO messages VALUES (?, ?, ?)", [
    ("old-1", "assistant", at(0, 10)), ("old-1", "assistant", at(0, 11)), ("old-1", "assistant", at(0, 12)),
    ("old-1", "user", at(0, 10)),
    ("old-2", "assistant", at(2, 9)),
  ])
  conn.commit()
  conn.close()


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  # Not signed in and nothing cached: the sessions show, and the panel says how to get the quota.
  assert record["usageStatusText"] == "Waiting for auth", repr(record["usageStatusText"])
  assert record["authHelpText"] == "Run `devin auth login` so Devin can record its quota.", repr(record["authHelpText"])
  assert record["tierLabel"] == "" and record["limits"] == [] and record["limitsFetchedAt"] == 0, (record["tierLabel"], record["limits"], record["limitsFetchedAt"])

  today, two_days_ago = date.today(), date.today() - timedelta(days=2)
  assert record["totalPrompts"] == 4 and record["todayPrompts"] == 3, (record["totalPrompts"], record["todayPrompts"])
  assert record["totalSessions"] == 2 and record["todaySessions"] == 1, (record["totalSessions"], record["todaySessions"])
  # With no split by kind the whole total is input; a session with no model is Devin's own.
  assert record["modelUsage"] == {
    "claude-sonnet-4-5": {"inputTokens": 12000, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
    "devin": {"inputTokens": 3000, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 12000 and record["todayTokensByModel"] == {"claude-sonnet-4-5": 12000}, (record["todayTotalTokens"], record["todayTokensByModel"])
  tokens = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert tokens[today.isoformat()] == 12000 and tokens[two_days_ago.isoformat()] == 3000 and sum(tokens.values()) == 15000, tokens
  assert record["activeDates"] == [two_days_ago.isoformat(), today.isoformat()], record["activeDates"]
