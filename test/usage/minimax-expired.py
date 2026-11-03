# SPDX-License-Identifier: GPL-3.0-only
# A machine with MINIMAX_API_KEY set, whose key MiniMax now refuses (answering
# 200 with an authentication code in base_resp), and which kept the limits of
# its last good check: one window still open and one whose reset has passed.

import sys
from pathlib import Path

TOKEN = "sk-FAKE-MINIMAX-GLOBAL"
KEPT = [
  {"label": "Session (5-hour)", "percent": 0.4, "resetsAt": "2099-01-01T00:00:00+00:00"},
  {"label": "Weekly (7-day)", "percent": 0.9, "resetsAt": "2020-01-01T00:00:00+00:00"},
]
SAVED_AT = []

ENV = {"MINIMAX_API_KEY": TOKEN}
ROUTES = [("/v1/token_plan/remains", {"base_resp": {"status_code": 1004, "status_msg": "login fail: Please carry the API secret key"}})]


def setup(home, bin):
  # The collector's own cache writer, so the kept answer is keyed as it keys it:
  # by the credential and the host it signs in to.
  sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
  from collectors import LimitsCache

  SAVED_AT[:] = [LimitsCache("minimax", "https://api.minimax.io", TOKEN).save(KEPT)]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.minimax.io/v1/token_plan/remains"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer " + TOKEN
  assert record["ready"] is True, "not ready"
  assert record["usageStatusText"] == "Sign-in expired", "status: " + repr(record["usageStatusText"])
  assert record["authHelpText"] == "MiniMax rejected the saved credentials. Set MINIMAX_API_KEY, or sign in to MiniMax again with `mmx` or opencode.", record["authHelpText"]
  # The kept windows stay, stale, with the lapsed one renewed: nothing used, no reset time.
  assert record["limits"] == [KEPT[0], {"label": "Weekly (7-day)", "percent": 0.0, "resetsAt": ""}], record["limits"]
  assert record["limitsStale"] is True and record["limitsFetchedAt"] == SAVED_AT[0], (record["limitsStale"], record["limitsFetchedAt"])
  assert record["tierLabel"] == "Token Plan", record["tierLabel"]
  assert record["hasLocalStats"] is False and record["modelUsage"] == {} and record["totalPrompts"] == 0, "local stats on a machine with no sessions"
  assert "retryAdvised" not in record, "a refused key is not an outage to retry"
