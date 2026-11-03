# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Grok on a unified-billing SuperGrok account (weekly
# credits and a monthly quota), with four sessions in ~/.grok: a typed one, a
# fork of it, a subagent's, and an old one.

import json
from datetime import date, datetime, time, timedelta, timezone

CREDITS = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
MONTHLY = "https://cli-chat-proxy.grok.com/v1/billing"
TOKEN = "xai-FAKE-ACCESS-TOKEN"


def local(days_ago, hour):
  return datetime.combine(date.today() - timedelta(days=days_ago), time(hour)).astimezone()


def zulu(moment):
  return moment.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def usage(**models):
  # Grok counts cached input inside inputTokens, and its totalTokens leaves
  # cache writes out.
  return {name: {**bucket, "totalTokens": bucket["inputTokens"] + bucket["outputTokens"]} for name, bucket in models.items()}


def write_session(home, folder, session, last_active, turns, kind=None):
  directory = home / ".grok" / "sessions" / folder / session
  directory.mkdir(parents=True, exist_ok=True)
  summary = {"last_active_at": zulu(last_active), "num_messages": 99}
  if kind:
    summary["session_kind"] = kind
  (directory / "summary.json").write_text(json.dumps(summary))
  (directory / "usage.json").write_text(json.dumps({"turns": turns}))


def setup(home, bin):
  grok = home / ".grok"
  grok.mkdir(exist_ok=True)
  (grok / "auth.json").write_text(json.dumps({"https://auth.x.ai": {
    "key": TOKEN, "refresh_token": "FAKE-GROK-REFRESH", "expires_at": "2099-01-01T00:00:00Z", "user_id": "user-FAKE-GROK",
  }}))
  (grok / "settings_cache.json").write_text(json.dumps({"payload": json.dumps({"settings": {"subscription_tier_display": "SuperGrok"}})}))

  first = {"endedAt": zulu(local(0, 12)), "modelUsage": usage(**{"grok-4": {"inputTokens": 1000, "cachedReadTokens": 400, "outputTokens": 250, "cacheCreationTokens": 50}})}
  second = {"endedAt": zulu(local(0, 13)), "modelUsage": usage(**{
    "grok-4": {"inputTokens": 500, "outputTokens": 100},
    "grok-code-fast": {"inputTokens": 200, "cachedReadTokens": 100, "outputTokens": 50},
  })}
  third = {"endedAt": zulu(local(2, 12)), "modelUsage": usage(**{"grok-4": {"inputTokens": 300, "cachedReadTokens": 100, "outputTokens": 80}})}
  write_session(home, "proj-a", "s1", local(0, 13), [first, second, third])
  # A fork repeats its source's turns before its own; the end time is epoch milliseconds here.
  own = {"endedAt": int(local(1, 12).timestamp() * 1000), "modelUsage": usage(**{"grok-4": {"inputTokens": 800, "cachedReadTokens": 300, "outputTokens": 120}})}
  write_session(home, "proj-a", "s2", local(0, 12), [first, own])
  # A subagent's tokens count, its prompts do not.
  spent = {"endedAt": zulu(local(1, 14)), "modelUsage": usage(**{"grok-code-fast": {"inputTokens": 100, "outputTokens": 40}})}
  write_session(home, "proj-b", "s3", local(1, 14), [spent], kind="subagent_explore")
  # Outside the week: in the totals and the model usage, not in the chart.
  old = {"endedAt": zulu(local(10, 12)), "modelUsage": usage(**{"grok-4": {"inputTokens": 100, "outputTokens": 10}})}
  write_session(home, "proj-c", "s4", local(10, 12), [old])


ROUTES = [
  (CREDITS, {"config": {
    "isUnifiedBillingUser": True,
    "creditUsagePercent": 42.5,
    "currentPeriod": {"type": "BILLING_PERIOD_TYPE_WEEKLY", "start": "2026-11-30T00:00:00Z", "end": "2026-12-07T00:00:00Z"},
  }}),
  (MONTHLY, {"config": {"monthlyLimit": {"val": 200}, "used": {"val": 50}, "billingPeriodEnd": "2027-01-01T00:00:00Z"}}),
]


def check(record, requests):
  assert record["id"] == "grok" and record["name"] == "Grok"
  assert record["ready"] is True and record["tierLabel"] == "SuperGrok", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Weekly", "percent": 0.425, "resetsAt": "2026-12-07T00:00:00+00:00"},
    {"label": "Monthly", "percent": 0.25, "resetsAt": "2027-01-01T00:00:00+00:00"},
  ], record["limits"]
  assert record["limitsStale"] is False and record["limitsFetchedAt"] > 0
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and "accounts" not in record

  today = date.today()
  week = [(today - timedelta(days=offset)).isoformat() for offset in range(6, -1, -1)]
  assert record["hasLocalStats"] is True and record["totalSessions"] == 4 and record["todaySessions"] == 2, (record["totalSessions"], record["todaySessions"])
  # The fork's copy of the first turn and the subagent's turn are not prompts.
  assert record["totalPrompts"] == 5 and record["todayPrompts"] == 2, (record["totalPrompts"], record["todayPrompts"])
  assert record["todayTotalTokens"] == 2150 and record["todayTokensByModel"] == {"grok-4": 1900, "grok-code-fast": 250}, record["todayTokensByModel"]
  assert record["recentDays"] == [{"date": day, "messageCount": {week[6]: 2150, week[5]: 1060, week[4]: 380}.get(day, 0)} for day in week], record["recentDays"]
  assert record["activeDays"] == 4 and record["activeDates"] == sorted([(today - timedelta(days=n)).isoformat() for n in (10, 2, 1, 0)]), record["activeDates"]
  assert record["modelUsage"] == {
    "grok-4": {"inputTokens": 1900, "outputTokens": 560, "cacheReadInputTokens": 800, "cacheCreationInputTokens": 50},
    "grok-code-fast": {"inputTokens": 200, "outputTokens": 90, "cacheReadInputTokens": 100, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]

  assert [r["url"] for r in requests] == [CREDITS, MONTHLY], [r["url"] for r in requests]
  for request in requests:
    assert request["method"] == "GET" and request["headers"]["authorization"] == f"Bearer {TOKEN}", "the sign-in was not sent"
