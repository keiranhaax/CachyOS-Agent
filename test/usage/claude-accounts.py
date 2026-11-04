# SPDX-License-Identifier: GPL-3.0-only
# A machine with five registered Claude Code accounts: the primary one in
# ~/.claude (Max, whose profile says 20x), a work one in a home of its own (a
# Team seat, the active account, with a registry id but no profile uuid), a
# spare that was registered and never signed in, an old one whose sign-in has
# lapsed with numbers kept from before, and an idle one whose access token has
# lapsed. Each live one is asked for its own limits with its own token; the
# record's top level describes the active account.

import json
import os
import time
from pathlib import Path

MAIN_TOKEN, WORK_TOKEN = "sk-ant-oat01-FAKE-MAIN", "sk-ant-oat01-FAKE-WORK"
WEEK = "2099-01-08T00:00:00+00:00"
MEASURED = int((time.time() - 3 * 3600) * 1000)
OLD = [{"label": "Weekly (7-day)", "percent": 0.8, "resetsAt": WEEK}]


def login(home, token, subscription, tier, expires_in=3600, refresh_expires_in=30 * 86400):
  home.mkdir(parents=True, exist_ok=True)
  (home / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {
    "accessToken": token, "expiresAt": int((time.time() + expires_in) * 1000),
    "refreshTokenExpiresAt": int((time.time() + refresh_expires_in) * 1000),
    "subscriptionType": subscription, "rateLimitTier": tier,
  }}))


def setup(home, bin):
  main, work, spare = home / ".claude", home / "accounts" / "claude-work", home / "accounts" / "claude-spare"
  old, idle = home / "accounts" / "claude-old", home / "accounts" / "claude-idle"
  login(main, MAIN_TOKEN, "max", "default_claude_max_5x")
  (home / ".claude.json").write_text(json.dumps({"oauthAccount": {"accountUuid": "acct-FAKE-main", "userRateLimitTier": "default_claude_max_20x"}}))
  login(work, WORK_TOKEN, "team", "default_claude_ai")
  (work / ".claude.json").write_text(json.dumps({"oauthAccount": {"emailAddress": "work@FAKE.example", "organizationRateLimitTier": "default_claude_max_5x"}}))
  spare.mkdir(parents=True, exist_ok=True)
  login(old, "sk-ant-oat01-FAKE-OLD", "pro", "default_claude_ai", expires_in=-7200, refresh_expires_in=-3600)
  login(idle, "sk-ant-oat01-FAKE-IDLE", "max", "default_claude_max_5x", expires_in=-3600)
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  cache.mkdir(parents=True, exist_ok=True)
  (cache / "claude-limits-acct-FAKE-old.json").write_text(json.dumps({"fetchedAtMs": MEASURED, "limits": OLD}))
  state = Path(os.environ["XDG_STATE_HOME"]) / "cachyos-agent" / "accounts"
  state.mkdir(parents=True, exist_ok=True)
  # The registry's plan and account id for the primary are out of date, it names
  # no home (so it is ~/.claude), and the spare's plan is all that is known of it.
  (state / "claude.json").write_text(json.dumps({
    "accounts": [
      {"id": "main", "label": "Personal", "email": "main@FAKE.example", "plan": "Pro", "accountId": "acct-FAKE-stale", "primary": True},
      {"id": "work", "label": "Work", "email": "work@FAKE.example", "plan": "", "accountId": "org/FAKE:2", "home": str(work)},
      {"id": "spare", "label": "Spare", "email": "spare@FAKE.example", "plan": "Pro", "home": str(spare)},
      {"id": "old", "label": "Old", "email": "old@FAKE.example", "plan": "", "accountId": "acct-FAKE-old", "home": str(old)},
      {"id": "idle", "label": "Idle", "email": "idle@FAKE.example", "plan": "", "home": str(idle)},
    ],
    "active": "work",
    "switch": "auto",
    "threshold": 90,
  }))


def usage(five_hour, seven_day):
  return {
    "five_hour": {"utilization": five_hour, "resets_at": "2099-01-01T05:00:00Z"},
    "seven_day": {"utilization": seven_day, "resets_at": "2099-01-08T00:00:00Z"},
  }


def by_token(request):
  return {"Bearer " + MAIN_TOKEN: usage(60, 30), "Bearer " + WORK_TOKEN: usage(10, 90)}[request.get_header("Authorization")]


ROUTES = [("/api/oauth/usage", by_token)]


def window(label, percent, resets_at):
  return {"label": label, "percent": percent, "resetsAt": resets_at}


def check(record, requests):
  main_limits = [window("Session (5-hour)", 0.6, "2099-01-01T05:00:00+00:00"), window("Weekly (7-day)", 0.3, WEEK)]
  work_limits = [window("Session (5-hour)", 0.1, "2099-01-01T05:00:00+00:00"), window("Weekly (7-day)", 0.9, WEEK)]
  # Each account is asked once with its own token; the others have none to send, or a lapsed one.
  assert sorted(r["headers"]["authorization"] for r in requests) == sorted(["Bearer " + MAIN_TOKEN, "Bearer " + WORK_TOKEN]), requests

  # The top level is the active account, the work one.
  assert record["ready"] is True and record["tierLabel"] == "Team 5x" and record["limits"] == work_limits, (record["tierLabel"], record["limits"])
  assert record["accountSwitch"] == {"mode": "auto", "threshold": 90}, record.get("accountSwitch")
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000, record["limitsFetchedAt"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and "retryAdvised" not in record, (record["usageStatusText"], sorted(record))

  assert [account["id"] for account in record["accounts"]] == ["main", "work", "spare", "old", "idle"]
  main, work, spare, old, idle = record["accounts"]
  assert (main["label"], main["email"], main["plan"], main["active"], main["primary"]) == ("Personal", "main@FAKE.example", "Max 20x", False, True), main
  assert (work["label"], work["email"], work["plan"], work["active"], work["primary"]) == ("Work", "work@FAKE.example", "Team 5x", True, False), work
  assert main["limits"] == main_limits and work["limits"] == work_limits, (main["limits"], work["limits"])
  for account in (main, work):
    assert account["stale"] is False and abs(time.time() * 1000 - account["fetchedAt"]) < 60_000, account
    assert account["usageStatusText"] == "" and account["authHelpText"] == "" and account["retryAdvised"] is False, account
  assert (spare["plan"], spare["active"], spare["primary"], spare["limits"], spare["stale"], spare["fetchedAt"]) == ("Pro", False, False, [], False, 0), spare
  assert spare["usageStatusText"] == "Waiting for auth" and spare["retryAdvised"] is False, spare
  assert (old["plan"], old["active"], old["limits"], old["stale"], old["fetchedAt"]) == ("Pro", False, OLD, True, MEASURED), old
  assert old["usageStatusText"] == "Sign-in expired", old["usageStatusText"]
  assert old["authHelpText"] == (
    "Claude Code's saved sign-in expired — showing the last known limits. Start Claude Code, or run `claude auth login`, to refresh it."
  ), old["authHelpText"]
  assert (idle["plan"], idle["limits"], idle["stale"], idle["fetchedAt"]) == ("Max 5x", [], False, 0), idle
  assert idle["usageStatusText"] == "Limits paused", idle["usageStatusText"]
  assert idle["authHelpText"] == "Claude Code's access token has lapsed. Start Claude Code to refresh it; signing in again is not needed.", idle["authHelpText"]
  assert "sk-ant-oat01" not in json.dumps(record), "the record leaks an access token"

  # Every account keeps its numbers under its own name: the primary's profile
  # uuid, the work account's registry id with the characters a file name cannot hold left out.
  cache = Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage"
  kept = {name: json.loads((cache / name).read_text())["limits"] for name in ("claude-limits-acct-FAKE-main.json", "claude-limits-orgFAKE2.json")}
  assert kept == {"claude-limits-acct-FAKE-main.json": main_limits, "claude-limits-orgFAKE2.json": work_limits}, kept
  assert sorted(p.name for p in cache.glob("claude-limits*")) == [
    "claude-limits-acct-FAKE-main.json", "claude-limits-acct-FAKE-old.json", "claude-limits-orgFAKE2.json",
  ], sorted(p.name for p in cache.iterdir())
