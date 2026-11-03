# SPDX-License-Identifier: GPL-3.0-only
# A machine with a Cursor token exported in the environment that the dashboard
# no longer accepts, and no earlier Grok Bot answer kept: the record stays
# unused, but says why.

ENV = {"CURSOR_AUTH_TOKEN": "cursor-FAKE-REFUSED-TOKEN"}
URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"

ROUTES = [("GetSandUsageStatus", (403, {"code": "permission_denied", "message": "forbidden"}))]


def check(record, requests):
  assert record["usageStatusText"] == "Sign-in expired", record["usageStatusText"]
  assert record["authHelpText"] == "Cursor refused the saved sign-in. Sign in to the Cursor editor, or run `cursor-agent login`, with your Grok Bot account.", record["authHelpText"]
  # A Cursor account that never had Grok Bot must not show up over a failed check.
  assert record["ready"] is False and record["limits"] == [] and record["limitsStale"] is True and record["limitsFetchedAt"] == 0
  assert [r["url"] for r in requests] == [URL], [r["url"] for r in requests]
  assert requests[0]["headers"]["authorization"] == "Bearer cursor-FAKE-REFUSED-TOKEN", "the exported token was not sent"
