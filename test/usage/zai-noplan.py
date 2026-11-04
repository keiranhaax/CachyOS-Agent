# SPDX-License-Identifier: GPL-3.0-only
# A pay-as-you-go Z.ai key: the monitor endpoint answers HTTP 200 that there is
# no coding plan behind it. The machine kept the limits of an earlier plan that
# has since lapsed, and opencode has one reply on Z.ai. The record shows local
# stats alone, with no trouble reported and the lapsed windows gone.

import hashlib
import json
import os
import sqlite3
import time
from datetime import date, datetime, time as clock
from pathlib import Path

KEY = "sk-FAKE-ZAI-PAYG"
ENV = {"ZAI_API_KEY": KEY}
ROUTES = [("/api/monitor/usage/quota/limit", {"code": 500, "msg": "Your account has no Coding Plan subscription", "success": False})]


def cache_path():
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  return Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"


def setup(home, bin):
  cache = cache_path()
  cache.parent.mkdir(parents=True, exist_ok=True)
  cache.write_text(json.dumps({
    "fetchedAtMs": int(time.time() * 1000) - 2 * 3600 * 1000,
    "limits": [{"label": "Session (5-hour)", "percent": 0.4, "resetsAt": "2099-01-01T00:00:00+00:00"}],
    "tierLabel": "Pro",
  }))
  db_path = home / ".local" / "share" / "opencode" / "opencode.db"
  db_path.parent.mkdir(parents=True, exist_ok=True)
  db = sqlite3.connect(db_path)
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  noon = int(datetime.combine(date.today(), clock(12)).timestamp() * 1000)
  db.execute("INSERT INTO message VALUES ('m1', 's1', 0, ?)", (json.dumps({
    "role": "assistant", "providerID": "zai", "modelID": "glm-4.6", "parentID": "u1", "time": {"created": noon},
    "tokens": {"input": 700, "output": 80, "reasoning": 0, "cache": {"read": 0, "write": 0}},
  }),))
  db.commit()
  db.close()


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True, "not ready"
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0, (record["limits"], record["limitsStale"], record["limitsFetchedAt"])
  assert record["tierLabel"] == "" and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["tierLabel"], record["usageStatusText"], record["authHelpText"])
  assert "retryAdvised" not in record
  assert record["hasLocalStats"] is True and record["totalPrompts"] == 1 and record["todayTotalTokens"] == 780, record["todayTotalTokens"]
  assert record["modelUsage"] == {"glm-4.6": {"inputTokens": 700, "outputTokens": 80, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}, record["modelUsage"]
  # The answer is kept as "no plan", with the lapsed plan's windows dropped.
  kept = json.loads(cache_path().read_text())
  assert kept["noWindows"] is True and kept["limits"] == [], kept
