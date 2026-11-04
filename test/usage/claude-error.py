# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage endpoint answers 500. Its numbers were measured
# five minutes ago, but a server error says nothing of waiting, so they are
# marked old.

import json
import os
import time
from pathlib import Path

TOKEN = "sk-ant-oat01-FAKE-ACCESS"
MEASURED = int((time.time() - 300) * 1000)
KEPT = [{"label": "Weekly (7-day)", "percent": 0.25, "resetsAt": "2099-01-08T00:00:00+00:00"}]


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / "claude-limits.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": KEPT}))


ROUTES = [("/api/oauth/usage", (500, {"type": "error", "error": {"type": "api_error", "message": "Internal server error"}}))]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["limits"] == KEPT, record["limits"]
  assert record["authHelpText"] == "Anthropic's usage endpoint returned status 500. Local Claude Code stats are still shown.", record["authHelpText"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "" and "retryAdvised" not in record, (record["usageStatusText"], sorted(record))
