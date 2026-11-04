# SPDX-License-Identifier: GPL-3.0-only
# A machine whose config file names a platform Z.ai does not have (so the
# global host answers) and whose monitor answer is rough: the 5-hour window has
# no percentage and the weekly one a flag for one, so neither is a meter; the
# rest are real. The answer carries no plan level.

import json
import os
from pathlib import Path

KEY = "sk-FAKE-ZAI-PARTIAL"


def setup(home, bin):
  config = Path(os.environ["XDG_CONFIG_HOME"]) / "cachyos-agent" / "zai.json"
  config.parent.mkdir(parents=True, exist_ok=True)
  config.write_text(json.dumps({"apiKey": KEY, "platform": "international"}))


ROUTES = [("/api/monitor/usage/quota/limit", {
  "success": True,
  "data": {"limits": [
    # No percentage: a false 0% would read as a fresh allowance, so no meter.
    {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "nextResetTime": 4070912400000},
    {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": True, "nextResetTime": 4070912400000},
    {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": "40", "nextResetTime": 4070912400000},
    {"type": "CREDIT_LIMIT", "unit": 6, "number": 1, "percentage": 0},
    "not a limit",
  ]},
})]


def check(record, requests):
  assert [r["url"] for r in requests] == ["https://api.z.ai/api/monitor/usage/quota/limit"], requests
  assert record["ready"] is True and record["tierLabel"] == "", (record["ready"], record["tierLabel"])
  # A real zero stays a meter, and a reset the answer leaves out is no reset.
  assert record["limits"] == [{"label": "Weekly (7-day)", "percent": 0.0, "resetsAt": ""}], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
