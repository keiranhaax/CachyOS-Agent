# SPDX-License-Identifier: GPL-3.0-only
# A machine with an OpenRouter inference key and no management key: the key's
# weekly credit limit reads, but OpenRouter answers the balance only to a
# management key, so there is none to show.

import json
import os
import shutil
from pathlib import Path

ENV = {"OPENROUTER_API_KEY": "sk-or-FAKE-INFERENCE"}


def setup(home, bin):
  # A refusal kept by an earlier run in this home would skip the request below.
  shutil.rmtree(home / ".cache" / "cachyos-agent", ignore_errors=True)

ROUTES = [
  ("/api/v1/key", {"data": {"limit": 10, "limit_remaining": 7.5, "limit_reset": "weekly", "is_management_key": False}}),
  ("/api/v1/credits", (403, {"error": {"code": 403, "message": "Only management keys can perform this operation"}})),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid"
  assert record["limits"] == [{"label": "Weekly key limit", "title": "Weekly key limit", "percent": 0.25, "resetsAt": ""}], record["limits"]
  # The refusal is no balance for this key, not a key gone bad: /key says that key still works.
  assert "balance" not in record and record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False
  assert [r["url"] for r in requests] == ["https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits"], [r["url"] for r in requests]
  assert all(r["headers"]["authorization"] == "Bearer sk-or-FAKE-INFERENCE" for r in requests)
  # It is kept, so the next refreshes do not ask again.
  cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "cachyos-agent" / "usage"
  refusals = [json.loads(path.read_text()).get("refused") for path in cache.glob("openrouter-credits-*.json")]
  assert refusals == [True], refusals
