# SPDX-License-Identifier: GPL-3.0-only
# A machine on Max 5x (a credential file that gives no expiry, so its token is
# used) whose usage endpoint answers with both flat windows unusable, a session
# utilization that is no number and a weekly one that is negative, a side
# bucket, and one model-scoped window. The scoped one is all that can be read.

import json

TOKEN = "sk-ant-oat01-FAKE-ACCESS"


def setup(home, bin):
  claude = home / ".claude"
  claude.mkdir(parents=True, exist_ok=True)
  (claude / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": TOKEN, "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x",
  }}))


ROUTES = [("/api/oauth/usage", {
  "five_hour": {"utilization": "n/a", "resets_at": "2099-01-01T05:00:00Z"},
  "seven_day": {"utilization": -3, "resets_at": "2099-01-08T00:00:00Z"},
  "seven_day_oauth_apps": {"utilization": 80.0, "resets_at": "2099-01-08T00:00:00Z"},
  "limits": [{
    "kind": "weekly_scoped", "scope": {"model": {"display_name": "Fable"}}, "percent": 41.5, "resets_at": "2099-01-08T00:00:00Z",
  }],
})]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Max 5x", (record["ready"], record["tierLabel"])
  assert [r["url"] for r in requests] == ["https://api.anthropic.com/api/oauth/usage"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer " + TOKEN, "a token with no expiry was not used"
  assert record["limits"] == [
    {"label": "Fable Weekly", "title": "Fable Weekly", "percent": 0.415, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False, (record["usageStatusText"], record["authHelpText"])
