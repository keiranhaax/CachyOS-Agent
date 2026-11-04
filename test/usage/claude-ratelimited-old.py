# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage endpoint answers 429 without saying how long
# to wait. Its numbers were measured an hour ago, which is too old to call
# current, so they are marked old.

import io
import json
import os
import time
import urllib.error
from email.message import Message
from pathlib import Path

TOKEN = "sk-ant-oat01-FAKE-BUSY"
MEASURED = int((time.time() - 3600) * 1000)
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


def busy(request):
  raise urllib.error.HTTPError(request.full_url, 429, "Too Many Requests", Message(), io.BytesIO(b"{}"))


ROUTES = [("/api/oauth/usage", busy)]


def check(record, requests):
  assert record["ready"] is True and record["limits"] == KEPT, (record["ready"], record["limits"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["authHelpText"] == "Anthropic's usage endpoint is rate limiting checks right now. Local Claude Code stats are still shown.", record["authHelpText"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "" and "retryAdvised" not in record, (record["usageStatusText"], sorted(record))
