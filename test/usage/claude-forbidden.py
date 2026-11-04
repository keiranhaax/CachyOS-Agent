# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x whose token the usage endpoint refuses with 403, with no
# earlier numbers to show. Claude Code has answered a prompt today.

import json
import time
from datetime import datetime, timezone

TOKEN = "sk-ant-oat01-FAKE-FORBIDDEN"
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
    + json.dumps({
      "type": "assistant", "uuid": "a1", "sessionId": "s1", "requestId": "r1", "timestamp": NOW,
      "message": {"id": "m1", "role": "assistant", "model": "claude-sonnet-4-5", "usage": {"input_tokens": 10, "output_tokens": 5}},
    }) + "\n"
  )


ROUTES = [("/api/oauth/usage", (403, {"type": "error", "error": {"type": "permission_error", "message": "OAuth authentication is currently not allowed."}}))]


def check(record, requests):
  # The local stats alone make the machine ready.
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert record["todayPrompts"] == 1 and record["modelUsage"]["claude-sonnet-4-5"]["inputTokens"] == 10, record["modelUsage"]
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Anthropic refused Claude Code's sign-in. Start Claude Code, or run `claude auth login`, to sign in again.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False and record["limitsFetchedAt"] == 0, (record["limits"], record["limitsStale"])
  assert "retryAdvised" not in record
