# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage panel is opened again seconds after the last
# check, without --force: the numbers kept five seconds ago stand in for a
# request, and are current.

import json
import os
import time
from pathlib import Path

ARGS = []
MEASURED = int((time.time() - 5) * 1000)
KEPT = [{"label": "Session (5-hour)", "percent": 0.9, "resetsAt": "2099-01-01T05:00:00+00:00"}]


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": "sk-ant-oat01-FAKE-ACCESS", "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / "claude-limits.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": KEPT}))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert record["limits"] == KEPT, record["limits"]
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
