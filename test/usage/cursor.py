# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to the Cursor CLI on a monthly Pro+ plan, with a week of
# token events on the dashboard: two models today, one two days ago.

import base64
import json
import os
from datetime import date, datetime, timedelta
from pathlib import Path


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


# Valid until 2100, so a token that has not lapsed is not read as one.
TOKEN = jwt({"sub": "user_FAKE_CURSOR", "exp": 4102444800})
BASE = "https://api2.cursor.sh/aiserver.v1.DashboardService/"
RESET = "2027-01-01T00:00:00+00:00"  # billingCycleEnd 1798761600000


def setup(home, bin):
  auth = Path(os.environ["XDG_CONFIG_HOME"]) / "cursor" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"accessToken": TOKEN, "refreshToken": "FAKE-CURSOR-REFRESH"}))


# Connect's JSON writes 64-bit counts as strings and leaves out what is empty.
EVENTS = {
  0: [
    {"modelIntent": "claude-4.5-sonnet", "inputTokens": "600", "outputTokens": "120", "cacheReadTokens": "3000", "cacheWriteTokens": "100"},
    {"modelIntent": "claude-4.5-sonnet", "inputTokens": "400", "outputTokens": "80", "cacheReadTokens": "2000", "cacheWriteTokens": "200"},
    {"modelIntent": "gpt-5", "inputTokens": 400, "outputTokens": 100, "cacheReadTokens": 50},
  ],
  2: [
    {"modelIntent": "claude-4.5-sonnet", "inputTokens": "700", "outputTokens": "50"},
    {"inputTokens": "10", "outputTokens": "5"},
  ],
}


# The day a request asks about is the local day its start midnight falls on.
def aggregations(request):
  start = int(json.loads(request.data)["startDate"])
  rows = EVENTS.get((date.today() - datetime.fromtimestamp(start / 1000).date()).days)
  return {"aggregations": rows} if rows else {}


ROUTES = [
  ("GetCurrentPeriodUsage", {
    "billingCycleStart": "1796083200000",
    "billingCycleEnd": "1798761600000",
    # Spend runs past the allowance (bonus usage), so a percentage worked out
    # from it would read 100% where Cursor's own meters read less.
    "planUsage": {"totalSpend": 9000, "limit": 7000, "totalPercentUsed": 46.25, "autoPercentUsed": 12.5, "apiPercentUsed": 80},
    "spendLimitUsage": {"individualLimit": 5000, "individualUsed": 1250},
  }),
  ("GetPlanInfo", {"planInfo": {"planName": "Pro+", "includedAmountCents": 7000}}),
  ("GetAggregatedUsageEvents", aggregations),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro+", (record["ready"], record["tierLabel"])
  assert record["scope"] == "account" and record["hasPromptStats"] is False
  assert record["limits"] == [
    {"label": "Included total", "title": "Monthly", "percent": 0.4625, "resetsAt": RESET},
    {"label": "Auto models", "title": "Auto models Monthly", "percent": 0.125, "resetsAt": RESET},
    {"label": "Named models", "title": "Named models Monthly", "percent": 0.8, "resetsAt": RESET},
    {
      "label": "On-demand $12.50 / $50.00", "title": "On-demand $12.50 / $50.00 Monthly",
      "percent": 0.25, "resetsAt": RESET, "onDemandLimitCents": 5000,
    },
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert record["limitsFetchedAt"] > 0

  today = date.today()
  week = [(today - timedelta(days=offset)).isoformat() for offset in range(6, -1, -1)]
  assert record["hasLocalStats"] is True
  assert record["todayTotalTokens"] == 7050 and record["todayTokensByModel"] == {"claude-4.5-sonnet": 6500, "gpt-5": 550}, record["todayTokensByModel"]
  assert record["recentDays"] == [{"date": day, "messageCount": {week[6]: 7050, week[4]: 765}.get(day, 0)} for day in week], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == [week[4], week[6]], record["activeDates"]
  assert record["modelUsage"] == {
    "claude-4.5-sonnet": {"inputTokens": 1700, "outputTokens": 250, "cacheReadInputTokens": 5000, "cacheCreationInputTokens": 300},
    "gpt-5": {"inputTokens": 400, "outputTokens": 100, "cacheReadInputTokens": 50, "cacheCreationInputTokens": 0},
    # A row that names no model is the CLI's own.
    "cursor": {"inputTokens": 10, "outputTokens": 5, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]

  assert sorted(r["url"] for r in requests) == sorted(
    [BASE + "GetCurrentPeriodUsage", BASE + "GetPlanInfo"] + [BASE + "GetAggregatedUsageEvents"] * 7
  ), [r["url"] for r in requests]
  for request in requests:
    assert request["method"] == "POST" and request["headers"]["authorization"] == f"Bearer {TOKEN}", "the sign-in was not sent"
  starts = sorted(int(json.loads(r["body"])["startDate"]) for r in requests if r["url"].endswith("GetAggregatedUsageEvents"))
  assert len(set(starts)) == 7, "the week is not seven different days"
