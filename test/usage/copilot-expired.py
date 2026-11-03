# SPDX-License-Identifier: GPL-3.0-only
# A machine whose COPILOT_QUOTA_TOKEN GitHub now refuses (401), with one session
# in the CLI's transcripts: no allowance is known, the local stats still show,
# and the panel is told to sign in again.

import json
from datetime import datetime, timezone

ENV = {"COPILOT_QUOTA_TOKEN": "gho_FAKE-expired"}

ROUTES = [("api.github.com/copilot_internal/user", (401, {"message": "Bad credentials"}))]


def setup(home, bin):
  session = home / ".copilot" / "session-state" / "sess-FAKE-1"
  session.mkdir(parents=True)
  stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
  (session / "events.jsonl").write_text(json.dumps({"type": "user.message", "timestamp": stamp, "data": {"content": "FAKE prompt"}}) + "\n")


def check(record, requests):
  assert record["ready"] is True and record["totalPrompts"] == 1 and record["totalSessions"] == 1
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == (
    "GitHub refused the token for Copilot's quota. Run `gh auth login`, or set COPILOT_QUOTA_TOKEN, to show Copilot's monthly allowance."
  ), record["authHelpText"]
  assert record["limits"] == [] and record["tierLabel"] == "" and record["limitsFetchedAt"] == 0
  assert "retryAdvised" not in record, "a refused token is not a network that is down"
  assert [r["url"] for r in requests] == ["https://api.github.com/copilot_internal/user"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer gho_FAKE-expired"
