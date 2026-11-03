# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to the Cursor CLI with an account that has a Grok Bot
# allowance, 37.5% of this week's included usage gone.

import base64
import json
import os
from pathlib import Path


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


# Valid until 2100, so a token that has not lapsed is not read as one.
TOKEN = jwt({"sub": "user_FAKE_GROKBOT", "exp": 4102444800})
URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"


def setup(home, bin):
  auth = Path(os.environ["XDG_CONFIG_HOME"]) / "cursor" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"accessToken": TOKEN, "refreshToken": "FAKE-CURSOR-REFRESH"}))


ROUTES = [("GetSandUsageStatus", {
  "hasNonZeroIncludedLimit": True,
  "usagePercent": 37.5,
  "nextResetTimestampUtc": "2026-12-07T09:30:00Z",
  "grokPlanLabel": "SuperGrok Heavy",
})]


def check(record, requests):
  assert record["id"] == "grokbot" and record["name"] == "Grok Bot"
  assert record["ready"] is True and record["tierLabel"] == "SuperGrok Heavy", (record["ready"], record["tierLabel"])
  assert record["limits"] == [{"label": "Weekly", "percent": 0.375, "resetsAt": "2026-12-07T09:30:00+00:00"}], record["limits"]
  assert record["limitsStale"] is False and record["limitsFetchedAt"] > 0
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["hasPromptStats"] is False and record["hasLocalStats"] is False
  assert [r["url"] for r in requests] == [URL], [r["url"] for r in requests]
  assert requests[0]["method"] == "POST" and requests[0]["headers"]["authorization"] == f"Bearer {TOKEN}", "the sign-in was not sent"
