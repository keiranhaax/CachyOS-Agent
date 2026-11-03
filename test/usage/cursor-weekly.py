# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to the Cursor CLI on a plan whose included allowance
# resets every week, with an on-demand budget spent to its limit.

import json
import os
from pathlib import Path

TOKEN = "cursor-FAKE-OPAQUE-TOKEN"
BASE = "https://api2.cursor.sh/aiserver.v1.DashboardService/"


def setup(home, bin):
  auth = Path(os.environ["XDG_CONFIG_HOME"]) / "cursor" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"accessToken": TOKEN}))


ROUTES = [
  ("GetCurrentPeriodUsage", {
    "billingCycleEnd": "1798761600000",
    "planUsage": {"totalPercentUsed": 62.5, "autoPercentUsed": 25, "apiPercentUsed": 130},
    "spendLimitUsage": {"individualLimit": 2000, "individualUsed": 2000},
  }),
  # The weekly reset is in epoch seconds here, billingCycleEnd in milliseconds.
  ("GetPlanInfo", {"planInfo": {"planName": "Ultra", "includedUsagePeriod": "INCLUDED_USAGE_PERIOD_WEEKLY", "includedUsageResetsAt": "1798156800"}}),
  ("GetAggregatedUsageEvents", {}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Ultra", (record["ready"], record["tierLabel"])
  week, cycle = "2026-12-25T00:00:00+00:00", "2027-01-01T00:00:00+00:00"
  assert record["limits"] == [
    {"label": "Included total", "title": "Weekly", "percent": 0.625, "resetsAt": week},
    {"label": "Auto models", "title": "Auto models Weekly", "percent": 0.25, "resetsAt": week},
    # Past 100% reads as 100%.
    {"label": "Named models", "title": "Named models Weekly", "percent": 1.0, "resetsAt": week},
    # The on-demand budget runs on the billing cycle whatever the allowance does.
    {
      "label": "On-demand $20.00 / $20.00", "title": "On-demand $20.00 / $20.00 Monthly",
      "percent": 1.0, "resetsAt": cycle, "onDemandLimitCents": 2000,
    },
  ], record["limits"]
  assert record["hasLocalStats"] is False and record["todayTotalTokens"] == 0
  urls = sorted(r["url"] for r in requests)
  assert urls == sorted([BASE + "GetCurrentPeriodUsage", BASE + "GetPlanInfo"] + [BASE + "GetAggregatedUsageEvents"] * 7), urls
  assert all(r["headers"]["authorization"] == f"Bearer {TOKEN}" for r in requests), "the sign-in was not sent"
