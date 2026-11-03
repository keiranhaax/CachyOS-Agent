# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to OpenRouter in opencode (an inference key with a daily
# credit limit) that also has a management key in openrouter.json, so the
# account's 30-day history and balance are read instead of local sessions.

import json
from datetime import date, timedelta

TODAY = date.today()
YESTERDAY = TODAY - timedelta(days=1)
LONG_AGO = TODAY - timedelta(days=10)


def setup(home, bin):
  opencode = home / ".local" / "share" / "opencode"
  opencode.mkdir(parents=True, exist_ok=True)
  (opencode / "auth.json").write_text(json.dumps({"openrouter": {"type": "api", "key": "sk-or-FAKE-INFERENCE"}}))
  config = home / ".config" / "cachyos-agent"
  config.mkdir(parents=True, exist_ok=True)
  (config / "openrouter.json").write_text(json.dumps({"managementKey": "sk-or-FAKE-MANAGEMENT"}))


def activity_row(day, slug, prompt, completion, reasoning):
  return {
    "date": f"{day.isoformat()} 00:00:00", "model": slug.split("-2025")[0], "model_permaslug": slug, "endpoint_id": "ep-1",
    "provider_name": "Provider", "usage": 1.5, "requests": 5,
    "prompt_tokens": prompt, "completion_tokens": completion, "reasoning_tokens": reasoning,
  }


ROUTES = [
  ("/api/v1/activity", {"data": [
    activity_row(TODAY, "anthropic/claude-4-sonnet-20250522", 1200, 300, 120),
    # Reasoning is part of the completion count; a row that names only reasoning still counts it.
    activity_row(TODAY, "openai/gpt-5-2025-08-07", 400, 0, 90),
    activity_row(YESTERDAY, "anthropic/claude-4-sonnet-20250522", 800, 200, 0),
    activity_row(LONG_AGO, "anthropic/claude-4-sonnet-20250522", 100, 50, 0),
  ]}),
  ("/api/v1/key", {"data": {"limit": 25, "limit_remaining": 5, "limit_reset": "daily", "is_management_key": False}}),
  ("/api/v1/credits", {"data": {"total_credits": 200, "total_usage": 150.5}}),
]


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Prepaid"
  assert record["scope"] == "account" and record["hasPromptStats"] is False and record["hasLocalStats"] is True
  assert record["todayTotalTokens"] == 1990 and record["todayTokensByModel"] == {"claude-4-sonnet-20250522": 1500, "gpt-5-2025-08-07": 490}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    "claude-4-sonnet-20250522": {"inputTokens": 2100, "outputTokens": 550, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
    "gpt-5-2025-08-07": {"inputTokens": 400, "outputTokens": 90, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["recentDays"][-2:] == [{"date": YESTERDAY.isoformat(), "messageCount": 1000}, {"date": TODAY.isoformat(), "messageCount": 1990}], record["recentDays"]
  # A day outside the last week still counts as a day of use.
  assert record["activeDays"] == 3 and record["activeDates"] == [LONG_AGO.isoformat(), YESTERDAY.isoformat(), TODAY.isoformat()], record["activeDates"]
  assert record["totalPrompts"] == 0

  assert record["limits"] == [{"label": "Daily key limit", "title": "Daily key limit", "percent": 0.8, "resetsAt": ""}], record["limits"]
  assert record.get("balance") == {"remaining": 49.5, "funded": 200.0, "spent": 150.5, "currency": "USD", "estimated": False}, record.get("balance")
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False

  # The account asks with the management key, the key's own meter with the inference key.
  sent = {r["url"].removeprefix("https://openrouter.ai/api/v1"): r["headers"]["authorization"] for r in requests}
  assert sent == {
    "/activity": "Bearer sk-or-FAKE-MANAGEMENT", "/key": "Bearer sk-or-FAKE-INFERENCE", "/credits": "Bearer sk-or-FAKE-MANAGEMENT",
  } and len(requests) == 3, [r["url"] for r in requests]
