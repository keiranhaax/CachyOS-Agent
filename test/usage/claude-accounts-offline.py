# SPDX-License-Identifier: GPL-3.0-only
# A machine with two registered Claude Code accounts: the primary one in
# ~/.claude (Max 5x, no profile, so it keeps the single-account cache), and a
# travel one, the active account, whose home has a profile and whose usage
# check cannot reach Anthropic. Its numbers from three hours ago stay, and the
# record's top level says what that account's does.

import json
import os
import time
import urllib.error
from pathlib import Path

MAIN_TOKEN, TRAVEL_TOKEN = "sk-ant-oat01-FAKE-MAIN", "sk-ant-oat01-FAKE-TRAVEL"
MEASURED = int((time.time() - 3 * 3600) * 1000)
WEEK = "2099-01-08T00:00:00+00:00"
KEPT = [{"label": "Weekly (7-day)", "percent": 0.8, "resetsAt": WEEK}]
LIVE = [{"label": "Weekly (7-day)", "percent": 0.3, "resetsAt": WEEK}]


def login(home, token, subscription, tier):
  home.mkdir(parents=True, exist_ok=True)
  (home / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": token, "expiresAt": int((time.time() + 3600) * 1000),
    "subscriptionType": subscription, "rateLimitTier": tier,
  }}))


def setup(home, bin):
  main, travel = home / ".claude", home / "accounts" / "claude-travel"
  login(main, MAIN_TOKEN, "max", "default_claude_max_5x")
  login(travel, TRAVEL_TOKEN, "pro", "default_claude_ai")
  (travel / ".claude.json").write_text(json.dumps({"oauthAccount": {"accountUuid": "acct-FAKE-travel"}}))
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / "claude-limits-acct-FAKE-travel.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": KEPT}))
  state = Path(os.environ["XDG_STATE_HOME"]) / "cachyos-agent" / "accounts"
  state.mkdir(parents=True, exist_ok=True)
  (state / "claude.json").write_text(json.dumps({
    "accounts": [
      {"id": "main", "label": "Personal", "email": "main@FAKE.example", "plan": "", "primary": True},
      {"id": "travel", "label": "Travel", "email": "travel@FAKE.example", "plan": "", "home": str(travel)},
    ],
    "active": "travel",
    "switch": "manual",
    "threshold": 99,
  }))


def usage(request):
  if request.get_header("Authorization") == "Bearer " + TRAVEL_TOKEN:
    raise urllib.error.URLError("no route to host")
  return {"seven_day": {"utilization": 30, "resets_at": "2099-01-08T00:00:00Z"}}


ROUTES = [("/api/oauth/usage", usage)]


def check(record, requests):
  assert sorted(r["headers"]["authorization"] for r in requests) == sorted(["Bearer " + MAIN_TOKEN, "Bearer " + TRAVEL_TOKEN]), requests

  # The top level is the travel account's: its plan, the numbers it kept, how old they are, and why.
  assert record["ready"] is True and record["tierLabel"] == "Pro" and record["limits"] == KEPT, (record["tierLabel"], record["limits"])
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == MEASURED, (record["limitsStale"], record["limitsFetchedAt"])
  assert record["usageStatusText"] == "", record["usageStatusText"]
  assert record["authHelpText"] == "Couldn't reach Anthropic's usage endpoint. Retrying shortly. Local Claude Code stats are still shown.", record["authHelpText"]
  assert record["retryAdvised"] is True, "no retry was advised"
  assert record["accountSwitch"] == {"mode": "manual", "threshold": 99}, record.get("accountSwitch")

  main, travel = record["accounts"]
  assert (main["id"], main["plan"], main["active"], main["primary"], main["limits"], main["stale"]) == ("main", "Max 5x", False, True, LIVE, False), main
  assert main["usageStatusText"] == "" and main["authHelpText"] == "" and main["retryAdvised"] is False, main
  assert (travel["id"], travel["plan"], travel["active"], travel["limits"], travel["stale"], travel["fetchedAt"]) == ("travel", "Pro", True, KEPT, True, MEASURED), travel
  assert travel["retryAdvised"] is True and travel["authHelpText"] == record["authHelpText"], travel

  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept = {name: json.loads((cache / name).read_text())["limits"] for name in ("claude-limits.json", "claude-limits-acct-FAKE-travel.json")}
  assert kept == {"claude-limits.json": LIVE, "claude-limits-acct-FAKE-travel.json": KEPT}, kept
  assert sorted(p.name for p in cache.glob("claude-limits*")) == sorted(kept), sorted(p.name for p in cache.iterdir())
