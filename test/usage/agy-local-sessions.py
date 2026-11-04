# SPDX-License-Identifier: GPL-3.0-only
# A machine with no sign-in whose only trace of Antigravity is a conversation
# summary (no prompt in the history, no transcript): a session was in use, so
# the agent is, and the record waits for a sign-in.

import sqlite3
from datetime import date, datetime, time, timezone

NOON = datetime.combine(date.today(), time(12)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  database = root / "conversation_summaries.db"
  database.unlink(missing_ok=True)
  conn = sqlite3.connect(database)
  with conn:
    conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT, last_modified_time TEXT)")
    conn.execute("INSERT INTO conversation_summaries VALUES ('conv-1', ?)", (NOON,))
  conn.close()


def check(record, requests):
  assert requests == []
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert (record["totalPrompts"], record["totalSessions"], record["todaySessions"]) == (0, 1, 1), record
  assert record["modelUsage"] == {} and record["activeDates"] == [date.today().isoformat()], record["activeDates"]
