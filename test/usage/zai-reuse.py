# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Z.ai limits were read five seconds ago (the panel was opened
# and closed again): a run without --force stands on that answer and asks
# Z.ai nothing.

import hashlib
import json
import os
import time
from pathlib import Path

KEY = "sk-FAKE-ZAI-REUSE"
SAVED_AT = int(time.time() * 1000) - 5000
KEPT = [
  {"label": "Session (5-hour)", "percent": 0.3, "resetsAt": "2099-01-01T00:00:00+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.55, "resetsAt": "2099-01-08T00:00:00+00:00"},
]

ENV = {"ZAI_API_KEY": KEY}
ARGS = []


def setup(home, bin):
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"
  cache.parent.mkdir(parents=True, exist_ok=True)
  cache.write_text(json.dumps({"fetchedAtMs": SAVED_AT, "limits": KEPT, "tierLabel": "Pro"}))


def check(record, requests):
  assert requests == [], "Z.ai was asked again within seconds: " + repr([r["url"] for r in requests])
  assert record["ready"] is True and record["limits"] == KEPT and record["tierLabel"] == "Pro", (record["ready"], record["limits"], record["tierLabel"])
  # A recent probe stands in for a fresh one: not stale, stamped when it was made.
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == SAVED_AT, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
