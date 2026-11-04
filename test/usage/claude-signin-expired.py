# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Claude Code config home is moved with CLAUDE_CONFIG_DIR, on a
# Team seat, left so long that the refresh token has lapsed too. The home's own
# profile (not ~/.claude.json) gives the seat's organization tier, and nothing
# was ever measured, so there are no numbers to keep.

import json
import os
import time
from datetime import datetime, timezone

NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def setup(home, bin):
  claude = home / "claude-work"
  project = claude / "projects" / "-home-keiran-demo"
  project.mkdir(parents=True, exist_ok=True)
  os.environ["CLAUDE_CONFIG_DIR"] = str(claude)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": "sk-ant-oat01-FAKE-LAPSED", "expiresAt": int((time.time() - 7200) * 1000),
    "refreshTokenExpiresAt": int((time.time() - 3600) * 1000),
    "subscriptionType": "team", "rateLimitTier": "default_claude_ai",
  }}))
  # A seat with no tier of its own is limited by its organization's.
  (claude / ".claude.json").write_text(json.dumps({"oauthAccount": {
    "accountUuid": "acct-FAKE-0003", "userRateLimitTier": "", "organizationRateLimitTier": "default_claude_max_5x",
  }}))
  (home / ".claude.json").write_text(json.dumps({"oauthAccount": {"accountUuid": "acct-FAKE-OTHER", "userRateLimitTier": "default_claude_max_20x"}}))
  (project / "s1.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u1", "sessionId": "s1", "timestamp": NOW, "message": {"role": "user", "content": "hello"}}) + "\n"
  )


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["todayPrompts"] == 1, (record["ready"], record["todayPrompts"])
  assert record["tierLabel"] == "Team 5x", record["tierLabel"]
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Claude Code's saved sign-in expired. Start Claude Code, or run `claude auth login`, to refresh it.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0, (record["limits"], record["limitsStale"])
