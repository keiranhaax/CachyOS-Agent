# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Z.ai key in the environment (and a Zhipu one beside it, which
# the Z.ai key outranks), on a Coding Plan whose monitor answer lists the 5-hour
# and the weekly token windows and a monthly tool-call row. opencode has
# replies on Z.ai's coding-plan provider and on Zhipu's, and two that are not
# this subscription's: a `zai-proxy` gateway and an OpenAI reply that merely
# mentions "zai" (a custom agent of that name). A Z.ai answer from a moment ago
# is kept, which this run (--force) asks past.

import hashlib
import json
import os
import sqlite3
import time as clock
from datetime import date, datetime, time, timedelta
from pathlib import Path

KEY = "sk-FAKE-ZAI"
# A trailing space, as a copied export leaves one.
ENV = {"ZAI_API_KEY": KEY + " ", "ZHIPU_API_KEY": "sk-FAKE-ZHIPU"}


def local_ms(days_ago, hour):
  return int(datetime.combine(date.today() - timedelta(days=days_ago), time(hour)).timestamp() * 1000)


def reply(provider, model, parent, created, input_tokens, output_tokens, reasoning=0, cache_read=0, cache_write=0, **extra):
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent, "time": {"created": created},
    "tokens": {"input": input_tokens, "output": output_tokens, "reasoning": reasoning, "cache": {"read": cache_read, "write": cache_write}},
    **extra,
  })


def cache_path():
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  return Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"


def setup(home, bin):
  cache_path().parent.mkdir(parents=True, exist_ok=True)
  cache_path().write_text(json.dumps({
    "fetchedAtMs": int(clock.time() * 1000) - 5000,
    "limits": [{"label": "Session (5-hour)", "percent": 0.9, "resetsAt": "2099-01-01T00:00:00+00:00"}],
    "tierLabel": "Lite",
  }))
  db_path = home / ".local" / "share" / "opencode" / "opencode.db"
  db_path.parent.mkdir(parents=True, exist_ok=True)
  db_path.unlink(missing_ok=True)
  db = sqlite3.connect(db_path)
  db.execute("CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_created INTEGER)")
  db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
  db.executemany("INSERT INTO session VALUES (?, NULL, ?)", [("s1", local_ms(5, 9)), ("s2", local_ms(5, 9))])
  db.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [
    # Two steps answering one prompt, today.
    ("m1", "s1", reply("zai-coding-plan", "glm-4.6", "u1", local_ms(0, 10), 1000, 200, reasoning=50, cache_read=300, cache_write=40)),
    ("m2", "s1", reply("zai-coding-plan", "glm-4.6", "u1", local_ms(0, 11), 500, 100)),
    # Yesterday, on Zhipu's coding plan.
    ("m3", "s2", reply("zhipuai-coding-plan", "glm-4.5-air", "u2", local_ms(1, 15), 2000, 400)),
    ("m4", "s2", reply("zai-proxy", "glm-4.6", "u3", local_ms(0, 12), 9999, 9999)),
    ("m5", "s2", reply("openai", "gpt-5", "u4", local_ms(0, 13), 8888, 8888, agent="zai")),
  ])
  db.commit()
  db.close()


ROUTES = [("/api/monitor/usage/quota/limit", {
  "code": 200, "msg": "Operation successful", "success": True,
  "data": {
    "level": "PRO",
    "limits": [
      # The monthly tool-call row is not a token window: skipped without a word.
      {"type": "TIME_LIMIT", "unit": 5, "number": 1, "usage": 1000, "currentValue": 12, "remaining": 988, "percentage": 1, "nextResetTime": 4072000000000},
      {"type": "CREDIT_LIMIT", "unit": 3, "number": 5, "percentage": 42, "nextResetTime": 4070912400000},
      {"type": "CREDIT_LIMIT", "unit": 6, "number": 1, "percentage": 7.5, "nextResetTime": 4071513600000},
    ],
  },
})]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  # The answer's percentages are of 100; a record's are fractions.
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.42, "resetsAt": "2099-01-01T01:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 0.075, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
  assert record["limitsStale"] is False and abs(record["limitsFetchedAt"] / 1000 - datetime.now().timestamp()) < 120, record["limitsFetchedAt"]
  assert "retryAdvised" not in record
  # The answer replaced the one kept a moment ago, for the next run to reuse.
  kept = json.loads(cache_path().read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Pro" and kept["fetchedAtMs"] == record["limitsFetchedAt"], kept

  # This endpoint takes the raw key, with no Bearer prefix, on the global host.
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  headers = requests[0]["headers"]
  assert requests[0]["method"] == "GET" and headers["authorization"] == KEY, (requests[0]["method"], headers)
  assert headers["accept-language"] == "en-US,en" and headers["content-type"] == "application/json", headers

  yesterday, today = (date.today() - timedelta(days=1)).isoformat(), date.today().isoformat()
  assert record["hasLocalStats"] is True and record["totalPrompts"] == 2 and record["totalSessions"] == 2, (record["totalPrompts"], record["totalSessions"])
  assert record["todayPrompts"] == 1 and record["todaySessions"] == 1 and record["todayTotalTokens"] == 2190, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"glm-4.6": 2190}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "glm-4.6": {"inputTokens": 1500, "outputTokens": 350, "cacheReadInputTokens": 300, "cacheCreationInputTokens": 40},
    "glm-4.5-air": {"inputTokens": 2000, "outputTokens": 400, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": yesterday, "messageCount": 2400}, {"date": today, "messageCount": 2190}], record["recentDays"]
  assert record["activeDates"] == [yesterday, today]
