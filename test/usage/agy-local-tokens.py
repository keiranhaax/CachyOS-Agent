# SPDX-License-Identifier: GPL-3.0-only
# A machine with no sign-in whose only trace of Antigravity is a transcript
# with tokens (no history, no summaries): tokens were spent, so the agent is
# in use, and the record waits for a sign-in.

import json
from datetime import date, datetime, time, timezone

NOON = datetime.combine(date.today(), time(12)).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def setup(home, bin):
  logs = home / ".gemini" / "antigravity-cli" / "brain" / "conv-1" / ".system_generated" / "logs"
  logs.mkdir(parents=True, exist_ok=True)
  (logs / "transcript.jsonl").write_text(json.dumps({
    "created_at": NOON, "model": "gemini-3-pro", "usage": {"prompt_token_count": 100, "candidates_token_count": 20},
  }) + "\n")


def check(record, requests):
  assert requests == []
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert (record["totalPrompts"], record["totalSessions"]) == (0, 0), record
  assert record["modelUsage"] == {"gemini-3-pro": {"inputTokens": 100, "outputTokens": 20, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}}, record["modelUsage"]
  assert record["todayTotalTokens"] == 120, record["todayTotalTokens"]
