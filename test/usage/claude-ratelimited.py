# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage endpoint answers 429 and asks to wait 30
# seconds. Its numbers were measured five minutes ago, which still describes the
# account, so they are not marked old.

import io
import json
import os
import time
import urllib.error
from email.message import Message
from pathlib import Path

TOKEN = "sk-ant-oat01-FAKE-BUSY"
MEASURED = int((time.time() - 300) * 1000)
KEPT = [
  {"label": "Session (5-hour)", "percent": 0.4, "resetsAt": "2099-01-01T05:00:00+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.25, "resetsAt": "2099-01-08T00:00:00+00:00"},
]


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


# The driver answers an error without headers, so the reply is raised here.
def busy(request):
  headers = Message()
  headers["Retry-After"] = "30"
  raise urllib.error.HTTPError(request.full_url, 429, "Too Many Requests", headers, io.BytesIO(b'{"error": {"type": "rate_limit_error"}}'))


ROUTES = [("/api/oauth/usage", busy)]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["limits"] == KEPT, record["limits"]
  assert record["authHelpText"] == "Anthropic's usage endpoint is rate limiting checks right now (retry after 30s). Local Claude Code stats are still shown.", record["authHelpText"]
  # Numbers this recent are current enough, and a "wait" is not a sign-out.
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "" and "retryAdvised" not in record, (record["usageStatusText"], sorted(record))
