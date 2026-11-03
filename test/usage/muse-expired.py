# SPDX-License-Identifier: GPL-3.0-only
# A machine whose saved Muse sign-in Meta now refuses (401), with one session
# in the CLI's logs and no session index: the limits are unknown, the local
# stats still show, and the panel is told to sign in again.

import json
from datetime import datetime

NOW = datetime.now().astimezone()

ROUTES = [("api.meta.ai/muse-code/key", (401, {"error": "invalid_token"}))]


def setup(home, bin):
  config = home / ".config" / "muse"
  config.mkdir(parents=True)
  (config / "auth.json").write_text(json.dumps({"providers": {"meta": {"access_token": "muse-FAKE-expired"}}}))

  session = home / ".local" / "share" / "muse" / "sessions" / "sess-FAKE-1"
  session.mkdir(parents=True)
  completion = {"kind": "model_completed", "model": "muse-spark-1.3", "usage": {"input_tokens": 1200, "output_tokens": 300, "cache_read_tokens": 200}}
  (session / "session.jsonl").write_text(json.dumps({"recorded_at": int(NOW.timestamp() * 1_000_000), "id": "e1", "payload": {"event": completion}}) + "\n")


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Muse's saved sign-in was rejected. Run `muse login` to refresh it.", record["authHelpText"]
  assert record["limits"] == [] and record["tierLabel"] == "" and record["limitsFetchedAt"] == 0
  assert "retryAdvised" not in record, "a refused sign-in is not a network that is down"
  assert [r["url"] for r in requests] == ["https://api.meta.ai/muse-code/key"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer muse-FAKE-expired"

  # No index row for the session, so its completion counts as the prompt.
  assert record["totalPrompts"] == 1 and record["totalSessions"] == 1 and record["todayPrompts"] == 1
  assert record["modelUsage"] == {
    "muse-spark-1.3": {"inputTokens": 1000, "outputTokens": 300, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 1500 and record["todayTokensByModel"] == {"muse-spark-1.3": 1500}
