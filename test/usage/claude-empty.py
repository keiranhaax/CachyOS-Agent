# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose usage endpoint answers 200 with something other
# than the usage object (a JSON list), so there is no window to read.

import json
import time
from datetime import datetime, timezone

TOKEN = "sk-ant-oat01-FAKE-ACCESS"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def setup(home, bin):
  claude = home / ".claude"
  project = claude / "projects" / "-home-keiran-demo"
  project.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))
  (project / "s1.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u1", "sessionId": "s1", "timestamp": NOW, "message": {"role": "user", "content": "hello"}}) + "\n"
  )


ROUTES = [("/api/oauth/usage", [])]


def check(record, requests):
  assert record["ready"] is True and record["todayPrompts"] == 1, (record["ready"], record["todayPrompts"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["usageStatusText"] == "Claude limits unavailable", record["usageStatusText"]
  assert record["authHelpText"] == "Anthropic's usage endpoint returned no limits. Local Claude Code stats are still shown.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and "retryAdvised" not in record, (record["limits"], sorted(record))
