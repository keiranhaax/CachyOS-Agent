# SPDX-License-Identifier: GPL-3.0-only
# A machine that has used Synthetic through opencode but holds no key for it:
# the local stats show, the quotas are never asked for, and the record says
# it waits for a sign-in.

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
    "role": "assistant", "providerID": "synthetic", "modelID": "hf:zai-org/GLM-4.6", "parentID": "u1", "time": {"created": noon},
    "tokens": {"input": 700, "output": 80, "reasoning": 0, "cache": {"read": 0, "write": 0}},
  }),))
  db.commit()
  db.close()


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert record["authHelpText"].startswith("Set SYNTHETIC_API_KEY"), record["authHelpText"]
  assert record["limits"] == [] and record["limitsFetchedAt"] == 0
  assert record["totalPrompts"] == 1 and record["totalSessions"] == 1 and record["todayTotalTokens"] == 780, record["todayTotalTokens"]
  assert record["modelUsage"] == {"GLM-4.6": {"inputTokens": 700, "outputTokens": 80, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}
  assert requests == [], "the quotas were asked for without a key"
