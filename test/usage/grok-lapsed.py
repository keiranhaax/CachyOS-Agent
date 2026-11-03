# SPDX-License-Identifier: GPL-3.0-only
# A machine whose Grok access token lapsed six hours ago, as it does between
# runs, with a refresh token Grok will use the next time it starts.

import json
from datetime import datetime, timedelta, timezone


def setup(home, bin):
  grok = home / ".grok"
  grok.mkdir(exist_ok=True)
  lapsed = (datetime.now(timezone.utc) - timedelta(hours=6)).isoformat()
  (grok / "auth.json").write_text(json.dumps({"https://auth.x.ai": {
    "key": "xai-FAKE-LAPSED-TOKEN", "refresh_token": "FAKE-GROK-REFRESH", "expires_at": lapsed, "user_id": "user-FAKE-LAPSED",
  }}))
  (grok / "settings_cache.json").write_text(json.dumps({"payload": json.dumps({"settings": {"subscription_tier_display": "SuperGrok"}})}))


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "SuperGrok", (record["ready"], record["tierLabel"])
  assert record["usageStatusText"] == "Limits paused", record["usageStatusText"]
  assert record["authHelpText"] == "Grok's access token has lapsed. Start Grok to refresh it; signing in again is not needed.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is False
  assert requests == [], "a lapsed token was sent anyway"
