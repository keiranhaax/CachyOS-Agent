# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai key the monitor endpoint turns away with HTTP 401, and
# which kept the limits of its last good check: one window still open and one
# whose reset has passed.

import hashlib
import json
import os
import time
from pathlib import Path

KEY = "sk-FAKE-ZAI-REFUSED"
SAVED_AT = int(time.time() * 1000) - 2 * 3600 * 1000
KEPT = [
  {"label": "Session (5-hour)", "percent": 0.4, "resetsAt": "2099-01-01T00:00:00+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.9, "resetsAt": "2020-01-01T00:00:00+00:00"},
]

ENV = {"ZAI_API_KEY": KEY}
ROUTES = [("/api/monitor/usage/quota/limit", (401, {"code": 1001, "msg": "Authorization Token missing", "success": False}))]


def setup(home, bin):
  # The answer is kept for the key and the host it signed in to.
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"
  cache.parent.mkdir(parents=True, exist_ok=True)
  cache.write_text(json.dumps({"fetchedAtMs": SAVED_AT, "limits": KEPT, "tierLabel": "Pro"}))


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert requests[0]["headers"]["authorization"] == KEY, "the key was not sent"
  assert record["ready"] is True, "not ready"
  assert record["usageStatusText"] == "Sign-in expired", "status: " + repr(record["usageStatusText"])
  assert record["authHelpText"] == "Z.ai rejected the saved API key. Update it in ~/.config/cachyos-agent/zai.json or ZAI_API_KEY.", record["authHelpText"]
  # The kept windows stay, stale, with the lapsed one renewed: nothing used, no reset time.
  assert record["limits"] == [KEPT[0], {"label": "Weekly (7-day)", "percent": 0.0, "resetsAt": ""}], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == SAVED_AT, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["tierLabel"] == "Pro", record["tierLabel"]
  assert "retryAdvised" not in record, "a refused key is not an outage to retry"
