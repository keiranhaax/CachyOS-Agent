# SPDX-License-Identifier: GPL-3.0-only
# A machine on a Pro subscription whose saved token still looks fresh, but the
# usage endpoint refuses it (401). Three hours ago it answered, and one of the
# windows it measured has reset since.

import json
import os
import time
from pathlib import Path

TOKEN = "sk-ant-oat01-FAKE-REVOKED"
MEASURED = int((time.time() - 3 * 3600) * 1000)


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": "pro", "rateLimitTier": "default_claude_ai",
  }}))
  # No profile names the account, so the single-account cache is the one kept.
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / "claude-limits.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": [
    {"label": "Session (5-hour)", "percent": 0.8, "resetsAt": "2020-01-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 0.55, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ]}))


ROUTES = [("/api/oauth/usage", (401, {"type": "error", "error": {"type": "authentication_error", "message": "OAuth token has been revoked."}}))]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer " + TOKEN, "the token was not sent"
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Anthropic refused Claude Code's sign-in. Start Claude Code, or run `claude auth login`, to sign in again.", record["authHelpText"]
  # The last numbers stay, the window that has reset reads as untouched, and they are marked as old.
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.0, "resetsAt": ""},
    {"label": "Weekly (7-day)", "percent": 0.55, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert "retryAdvised" not in record
