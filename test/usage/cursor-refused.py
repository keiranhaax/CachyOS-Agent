# SPDX-License-Identifier: GPL-3.0-only
# A machine whose saved Cursor CLI sign-in the dashboard no longer accepts,
# with no earlier answer kept.

import json
import os
from pathlib import Path

TOKEN = "cursor-FAKE-REFUSED-TOKEN"
URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"


def setup(home, bin):
  auth = Path(os.environ["XDG_CONFIG_HOME"]) / "cursor" / "auth.json"
  auth.parent.mkdir(parents=True, exist_ok=True)
  auth.write_text(json.dumps({"accessToken": TOKEN}))


ROUTES = [("GetCurrentPeriodUsage", (401, {"code": "unauthenticated", "message": "invalid token"}))]


def check(record, requests):
  assert record["ready"] is True and record["usageStatusText"] == "Sign-in expired", (record["ready"], record["usageStatusText"])
  assert record["authHelpText"] == "Cursor refused the saved sign-in. Sign in to the Cursor editor, or run `cursor-agent login`.", record["authHelpText"]
  assert record["limits"] == [] and record["limitsStale"] is True and record["limitsFetchedAt"] == 0
  assert record["hasLocalStats"] is False
  # Nothing else is asked once the sign-in is turned away.
  assert [r["url"] for r in requests] == [URL], [r["url"] for r in requests]
  assert requests[0]["headers"]["authorization"] == f"Bearer {TOKEN}", "the sign-in was not sent"
