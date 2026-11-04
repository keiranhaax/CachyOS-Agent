# SPDX-License-Identifier: GPL-3.0-only
# A machine left alone overnight on Max 5x: the access token has lapsed, which
# is routine, and the refresh token has weeks left. The profile is the legacy
# .config.json inside the config home and names the account, whose last numbers
# are kept; another account's were kept too, under the single-account name.

import json
import os
import time
from pathlib import Path

ACCOUNT = "acct-FAKE-0002"
MEASURED = int((time.time() - 2 * 3600) * 1000)
WEEK = "2099-01-08T00:00:00+00:00"


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": "sk-ant-oat01-FAKE-LAPSED", "expiresAt": int((time.time() - 3600) * 1000),
    "refreshTokenExpiresAt": int((time.time() + 30 * 86400) * 1000),
    "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))
  (claude / ".config.json").write_text(json.dumps({"oauthAccount": {"accountUuid": ACCOUNT, "userRateLimitTier": "default_claude_max_20x"}}))
  # The home's own ~/.claude.json is not read when a legacy profile is there.
  (home / ".claude.json").write_text(json.dumps({"oauthAccount": {"accountUuid": "acct-FAKE-OTHER", "userRateLimitTier": "default_claude_max_5x"}}))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / f"claude-limits-{ACCOUNT}.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": [
    {"label": "Weekly (7-day)", "percent": 0.7, "resetsAt": WEEK},
  ]}))
  (cache / "claude-limits.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": [
    {"label": "Weekly (7-day)", "percent": 0.1, "resetsAt": WEEK},
  ]}))


def check(record, requests):
  # A lapsed token is never sent.
  assert requests == [], requests
  assert record["ready"] is True and record["tierLabel"] == "Max 20x", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "Limits paused", record["usageStatusText"]
  assert record["authHelpText"] == (
    "Claude Code's access token has lapsed — showing the last known limits. Start Claude Code to refresh it; signing in again is not needed."
  ), record["authHelpText"]
  assert record["limits"] == [{"label": "Weekly (7-day)", "percent": 0.7, "resetsAt": WEEK}], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
