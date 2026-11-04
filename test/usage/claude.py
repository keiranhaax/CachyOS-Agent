# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Claude Code on a Max subscription (a token with hours
# left), whose profile says the account has since moved to Max 20x. Claude Code
# has answered one prompt today. The usage endpoint lists the session and weekly
# windows and two model-scoped windows. A check five seconds ago left numbers
# behind, which a refresh (--force) does not take for an answer.

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

TOKEN = "sk-ant-oat01-FAKE-ACCESS"
ACCOUNT = "acct-FAKE-0001"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def setup(home, bin):
  claude = home / ".claude"
  project = claude / "projects" / "-home-keiran-demo"
  project.mkdir(parents=True, exist_ok=True)
  # The credentials still carry the tier their token was minted with.
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "refreshToken": "sk-ant-ort01-FAKE-REFRESH",
    "expiresAt": int((time.time() + 8 * 3600) * 1000), "refreshTokenExpiresAt": int((time.time() + 30 * 86400) * 1000),
    "scopes": ["user:inference", "user:profile"], "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))
  (home / ".claude.json").write_text(json.dumps({"oauthAccount": {
    "accountUuid": ACCOUNT, "emailAddress": "keiran@FAKE.example", "userRateLimitTier": "default_claude_max_20x",
  }}))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / f"claude-limits-{ACCOUNT}.json").write_text(json.dumps({
    "fetchedAtMs": int((time.time() - 5) * 1000), "limits": [{"label": "Session (5-hour)", "percent": 0.99, "resetsAt": ""}],
  }))
  (project / "s1.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u1", "sessionId": "s1", "timestamp": NOW, "message": {"role": "user", "content": "hello"}}) + "\n"
    + json.dumps({
      "type": "assistant", "uuid": "a1", "sessionId": "s1", "requestId": "r1", "timestamp": NOW,
      "message": {"id": "m1", "role": "assistant", "model": "claude-opus-4-1", "usage": {
        "input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 200}},
    }) + "\n"
  )


def scoped(kind, model, percent, resets_at):
  return {"kind": kind, "scope": {"model": model}, "percent": percent, "resets_at": resets_at}


REPLY = {
  "five_hour": {"utilization": 37.0, "resets_at": "2099-01-01T05:00:00.123456+00:00"},
  "seven_day": {"utilization": 62.5, "resets_at": "2099-01-08T00:00:00Z"},
  # A side bucket that Claude Code's own /usage never shows as the weekly limit,
  # and the legacy per-model keys, left at null; extra usage is not a window.
  "seven_day_oauth_apps": {"utilization": 99.0, "resets_at": "2099-01-09T00:00:00Z"},
  "seven_day_opus": None,
  "seven_day_sonnet": None,
  "extra_usage": {"is_enabled": True, "monthly_limit": 5000, "used_credits": 1234.0, "utilization": 24.68},
  "limits": [
    scoped("weekly_scoped", {"id": "claude-fable-5", "display_name": "Fable"}, 41.5, "2099-01-08T00:00:00Z"),
    scoped("five_hour_scoped", {"id": "claude-opus-5", "display_name": "Opus 5 (1M context)"}, 12, "2099-01-01T05:00:00Z"),
  ],
}
ROUTES = [("/api/oauth/usage", REPLY)]

LIMITS = [
  {"label": "Session (5-hour)", "percent": 0.37, "resetsAt": "2099-01-01T05:00:00.123456+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.625, "resetsAt": "2099-01-08T00:00:00+00:00"},
  {"label": "Fable Weekly", "title": "Fable Weekly", "percent": 0.415, "resetsAt": "2099-01-08T00:00:00+00:00"},
  {
    "label": "Opus 5 (1M context) Session", "title": "Opus 5 (1M context) Session",
    "percent": 0.12, "resetsAt": "2099-01-01T05:00:00+00:00",
  },
]


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  # The profile's tier outranks the credentials', and the subscription leads.
  assert record["tierLabel"] == "Max 20x", record["tierLabel"]
  assert record["limits"] == LIMITS, record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000, record["limitsFetchedAt"]
  assert not {"accounts", "accountSwitch", "retryAdvised"} & set(record), sorted(record)
  assert TOKEN not in json.dumps(record), "the record leaks the access token"

  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  request = requests[0]
  assert request["method"] == "GET" and request["headers"]["authorization"] == "Bearer " + TOKEN, "the token was not sent"
  assert request["headers"]["anthropic-beta"] == "oauth-2025-04-20" and request["headers"]["accept"] == "application/json", request["headers"]

  # The answer is kept under the account the profile names, for a later failed probe.
  kept = json.loads((Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"claude-limits-{ACCOUNT}.json").read_text())
  assert kept["limits"] == LIMITS and kept["fetchedAtMs"] == record["limitsFetchedAt"], kept

  assert (record["todayPrompts"], record["totalPrompts"], record["totalSessions"]) == (1, 1, 1), record["totalPrompts"]
  assert record["todayTotalTokens"] == 1350 and record["todayTokensByModel"] == {"claude-opus-4-1": 1350}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "claude-opus-4-1": {"inputTokens": 100, "outputTokens": 50, "cacheReadInputTokens": 1000, "cacheCreationInputTokens": 200},
  }, record["modelUsage"]
