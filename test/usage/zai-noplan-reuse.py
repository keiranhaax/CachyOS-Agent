# SPDX-License-Identifier: GPL-3.0-only
# A pay-as-you-go Z.ai key that was found to have no coding plan twenty minutes
# ago: a run without --force takes that for the answer (such a key is asked
# again hourly) and asks Z.ai nothing.

import hashlib
import json
import os
import time
from pathlib import Path

KEY = "sk-FAKE-ZAI-PAYG-REUSE"

ENV = {"ZAI_API_KEY": KEY}
ARGS = []


def setup(home, bin):
  digest = hashlib.sha256(f"zai\0{KEY}".encode()).hexdigest()[:16]
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"zai-limits-{digest}.json"
  cache.parent.mkdir(parents=True, exist_ok=True)
  cache.write_text(json.dumps({"fetchedAtMs": int(time.time() * 1000) - 20 * 60 * 1000, "limits": [], "tierLabel": "", "noWindows": True}))


def check(record, requests):
  assert requests == [], "Z.ai was asked again within the hour: " + repr([r["url"] for r in requests])
  assert record["ready"] is True and record["limits"] == [] and record["tierLabel"] == ""
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False and record["limitsFetchedAt"] == 0
