# SPDX-License-Identifier: GPL-3.0-only
# A machine that has used Kimchi through opencode but holds no Kimchi login:
# the local stats show, the gateway is never asked, and the record says it
# waits for a sign-in.

import json
import sqlite3
from datetime import date, datetime, time


def setup(home, bin):
  db_path = home / ".local" / "share" / "opencode" / "opencode.db"
  db_path.parent.mkdir(parents=True, exist_ok=True)
  db_path.unlink(missing_ok=True)
  db = sqlite3.connect(db_path)
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  noon = int(datetime.combine(date.today(), time(12)).timestamp() * 1000)
  db.execute("INSERT INTO message VALUES ('m1', 's1', 0, ?)", (json.dumps({
    "role": "assistant", "providerID": "kimchi", "modelID": "kimi-k2.5", "parentID": "u1", "time": {"created": noon},
    "tokens": {"input": 700, "output": 80, "reasoning": 0, "cache": {"read": 0, "write": 0}},
  }),))
  db.commit()
  db.close()


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True and record["tierLabel"] == ""
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert record["authHelpText"] == "Start Kimchi and log in, or set KIMCHI_API_KEY.", record["authHelpText"]
  assert record["limits"] == [] and "balance" not in record
  assert record["totalPrompts"] == 1 and record["totalSessions"] == 1 and record["todayTotalTokens"] == 780, record["todayTotalTokens"]
  assert record["modelUsage"] == {"kimi-k2.5": {"inputTokens": 700, "outputTokens": 80, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}
  assert requests == [], "the gateway was asked without a key"
