# SPDX-License-Identifier: GPL-3.0-only
# A machine that has run agy (a history with two prompts today in one
# conversation) but holds no usable sign-in (agy's token file has a refresh
# token and no access token): the local stats show, the quota is never asked
# for, and the record says it is waiting for a sign-in.

import json
from datetime import date, datetime, time, timedelta

NOON = datetime.combine(date.today(), time(12))


def setup(home, bin):
  root = home / ".gemini" / "antigravity-cli"
  root.mkdir(parents=True, exist_ok=True)
  # A token file with only a refresh token has nothing to ask Google with.
  (root / "antigravity-oauth-token").write_text(json.dumps({"refresh_token": "1//FAKE-ONLY-REFRESH", "auth_method": "consumer"}))
  (root / "history.jsonl").write_text("".join(
    json.dumps({"timestamp": int((NOON + timedelta(minutes=minutes)).timestamp() * 1000), "conversationId": "conv-1"}) + "\n" for minutes in (0, 3)
  ))


def check(record, requests):
  assert requests == [], "the quota was asked for without a sign-in"
  assert record["ready"] is True and record["hasLocalStats"] is True
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert record["authHelpText"] == "Run `agy` to sign in, or sign in to Antigravity in omp, pi, or opencode.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsFetchedAt"] == 0 and record["limitsStale"] is False and record["tierLabel"] == ""
  assert (record["todayPrompts"], record["totalPrompts"], record["todaySessions"], record["totalSessions"]) == (2, 2, 1, 1), record
  assert record["modelUsage"] == {} and record["activeDays"] == 1 and record["activeDates"] == [date.today().isoformat()], record["activeDates"]
