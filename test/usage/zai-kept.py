# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai monitor endpoint answers HTTP 200 with a refusal that is
# no sign-in problem ("insufficient balance", no data), and which kept the
# limits of its last good check on the Max plan: the key is not at fault, so the
# kept windows show, stale, with the reason beside them and no sign-in notice.

import hashlib
import json
import os
import time
from pathlib import Path

KEY = "sk-FAKE-ZAI-KEPT"
SAVED_AT = int(time.time() * 1000) - 3600 * 1000
KEPT = [
  {"label": "Session (5-hour)", "percent": 0.25, "resetsAt": "2099-01-01T00:00:00+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.6, "resetsAt": "2099-01-08T00:00:00+00:00"},
]

ENV = {"ZAI_API_KEY": KEY}
ROUTES = [("/api/monitor/usage/quota/limit", {"code": 1113, "msg": "Insufficient balance", "success": False})]


def setup(home, bin):
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"
  cache.parent.mkdir(parents=True, exist_ok=True)
  cache.write_text(json.dumps({"fetchedAtMs": SAVED_AT, "limits": KEPT, "tierLabel": "Max"}))


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["limits"] == KEPT, (record["ready"], record["limits"])
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == SAVED_AT, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["tierLabel"] == "Max", record["tierLabel"]
  assert record["usageStatusText"] == "", record["usageStatusText"]
  assert record["authHelpText"] == "Insufficient balance. Local stats are still shown.", record["authHelpText"]
  assert "retryAdvised" not in record
