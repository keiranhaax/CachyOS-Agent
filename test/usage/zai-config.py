# SPDX-License-Identifier: GPL-3.0-only
# A machine in China: ~/.config/cachyos-agent/zai.json holds a Zhipu (BigModel)
# key and says so, which outranks the Z.ai key still exported in the environment.
# The monitor answer is the older shape (TOKENS_LIMIT rows, a reset in epoch
# seconds) with one window over its allowance and one reported as negative.

import json
import os
from pathlib import Path

KEY = "sk-FAKE-ZHIPU-CONFIG"
ENV = {"ZAI_API_KEY": "sk-FAKE-ZAI-ENV"}


def setup(home, bin):
  config = Path(os.environ["XDG_CONFIG_HOME"]) / "cachyos-agent" / "zai.json"
  config.parent.mkdir(parents=True, exist_ok=True)
  config.write_text(json.dumps({"apiKey": f"  {KEY} ", "platform": " Zhipu "}))


ROUTES = [("/api/monitor/usage/quota/limit", {
  "code": 200, "success": True,
  "data": {
    "level": "lite",
    "limits": [
      {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": -3, "nextResetTime": 4070908800},
      {"type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 130, "nextResetTime": 4071513600000},
    ],
  },
})]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://open.bigmodel.cn/api/monitor/usage/quota/limit"], requests
  assert requests[0]["headers"]["authorization"] == KEY, "the config file's key was not sent as it stands, trimmed"
  assert record["ready"] is True and record["tierLabel"] == "Lite", (record["ready"], record["tierLabel"])
  # Below nothing used, above everything used; a seconds epoch is no date in the year 5000.
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.0, "resetsAt": "2099-01-01T00:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 1.0, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert record["limitsFetchedAt"] > 0, "no fetch time"
  assert record["hasLocalStats"] is False and record["modelUsage"] == {}, "local stats on a machine with no sessions"
