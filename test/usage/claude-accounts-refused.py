# SPDX-License-Identifier: GPL-3.0-only
# A machine with two registered Claude Code accounts, the second of them active
# and a Pro seat whose token Anthropic refuses (401), with nothing kept from
# before. Claude Code has answered a prompt today, which keeps the machine
# ready. The record's top level says what the active account's does.

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

MAIN_TOKEN, WORK_TOKEN = "sk-ant-oat01-FAKE-MAIN", "sk-ant-oat01-FAKE-WORK"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
REFUSED = "Anthropic refused Claude Code's sign-in. Start Claude Code, or run `claude auth login`, to sign in again."


def login(home, token, subscription, tier):
  home.mkdir(parents=True, exist_ok=True)
  (home / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": token, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": subscription, "rateLimitTier": tier,
  }}))


def setup(home, bin):
  main, work = home / ".claude", home / "accounts" / "claude-work"
  login(main, MAIN_TOKEN, "max", "default_claude_max_5x")
  login(work, WORK_TOKEN, "pro", "default_claude_ai")
  (main / "projects" / "-home-keiran-demo").mkdir(parents=True, exist_ok=True)
  (main / "projects" / "-home-keiran-demo" / "s1.jsonl").write_text(
    json.dumps({"type": "user", "uuid": "u1", "sessionId": "s1", "timestamp": NOW, "message": {"role": "user", "content": "hello"}}) + "\n"
  )
  state = Path(os.environ["XDG_STATE_HOME"]) / "cachyos-agent" / "accounts"
  state.mkdir(parents=True, exist_ok=True)
  (state / "claude.json").write_text(json.dumps({
    "accounts": [
      {"id": "main", "label": "Personal", "plan": "", "primary": True},
      {"id": "work", "label": "Work", "plan": "", "home": str(work)},
    ],
    "active": "work",
    "switch": "manual",
    "threshold": 99,
  }))


def usage(request):
  if request.get_header("Authorization") == "Bearer " + WORK_TOKEN:
    return 401, {"type": "error", "error": {"type": "authentication_error", "message": "OAuth token has been revoked."}}
  return {"seven_day": {"utilization": 30, "resets_at": "2099-01-08T00:00:00Z"}}


ROUTES = [("/api/oauth/usage", usage)]


def check(record, requests):
  assert sorted(r["headers"]["authorization"] for r in requests) == sorted(["Bearer " + MAIN_TOKEN, "Bearer " + WORK_TOKEN]), requests

  assert record["ready"] is True and record["todayPrompts"] == 1, (record["ready"], record["todayPrompts"])
  assert record["tierLabel"] == "Pro" and record["limits"] == [], (record["tierLabel"], record["limits"])
  assert record["usageStatusText"] == "Sign-in expired" and record["authHelpText"] == REFUSED, (record["usageStatusText"], record["authHelpText"])
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == 0 and "retryAdvised" not in record, (record["limitsStale"], sorted(record))

  main, work = record["accounts"]
  assert (main["plan"], main["active"], main["stale"], main["usageStatusText"]) == ("Max 5x", False, False, ""), main
  assert main["limits"] == [{"label": "Weekly (7-day)", "percent": 0.3, "resetsAt": "2099-01-08T00:00:00+00:00"}], main["limits"]
  assert (work["plan"], work["active"], work["limits"], work["stale"], work["fetchedAt"]) == ("Pro", True, [], False, 0), work
  assert work["usageStatusText"] == "Sign-in expired" and work["authHelpText"] == REFUSED and work["retryAdvised"] is False, work
