# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Kimi Code (a fresh OAuth token in ~/.kimi-code), on a
# plan whose usage answer lists its four windows. Kimi Code has run three
# sessions: today's, yesterday's, and a fork of today's that copies its first
# records. Its config.toml routes one model alias to Moonshot's API and one to
# DeepSeek's, which is not Kimi's.

import json
import time
from datetime import datetime, timedelta

TOKEN = "kimi-FAKE-ACCESS"
NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)
YESTERDAY = NOON - timedelta(days=1)
DAY = "%Y-%m-%d"
MANAGED = "kimi-code/kimi-for-coding"


def ms(moment):
  return int(moment.timestamp() * 1000)


def prompt(key, moment, origin=None):
  return {"type": "turn.prompt", "time": ms(moment), "promptId": key, "origin": origin or {"kind": "user"}}


def request(alias):
  return {"type": "llm.request", "modelAlias": alias}


def usage(moment, model, tokens, cache=(0, 0)):
  return {
    "type": "usage.record", "time": ms(moment), "agentId": "main", "model": model,
    "usage": {"inputOther": tokens[0], "output": tokens[1], "inputCacheRead": cache[0], "inputCacheCreation": cache[1]},
  }


BIND = {"type": "profile.bind", "modelAlias": MANAGED}
START = [BIND, prompt("p1", NOON), request(MANAGED), usage(NOON + timedelta(minutes=1), MANAGED, (100, 50), (200, 10))]
SESSIONS = {
  # A request on the DeepSeek alias is not Kimi's, nor the prompt it answers. A
  # skill the model started is not typed; one the user ran is.
  "ses1": START + [
    prompt("p2", NOON + timedelta(minutes=2)), request("deepseek/chat"), usage(NOON + timedelta(minutes=3), "deepseek/chat", (999, 999)),
    prompt("p3", NOON + timedelta(minutes=4), {"kind": "skill_activation", "trigger": "model"}),
    prompt("p5", NOON + timedelta(minutes=5), {"kind": "skill_activation", "trigger": "user-slash"}), request(MANAGED),
    usage(NOON + timedelta(minutes=6), MANAGED, (20, 10)),
  ],
  "ses2": [prompt("p4", YESTERDAY), request("moonshot/kimi-k2"), usage(YESTERDAY + timedelta(minutes=1), "moonshot/kimi-k2", (7, 3))],
  "ses3": START + [{"type": "forked"}],
}

CONFIG = """
[providers.moonshot]
type = "openai"
base_url = "https://api.moonshot.ai/v1"

[providers.deepseek]
type = "openai"
base_url = "https://api.deepseek.com/v1"

[models."moonshot/kimi-k2"]
provider = "moonshot"
model = "kimi-k2-0905"

[models."deepseek/chat"]
provider = "deepseek"
model = "deepseek-chat"
"""

ROUTES = [("/coding/v1/usages", {"usages": {
  # Nanoseconds are trimmed to the microseconds Python reads.
  "limit_5h": {"used_ratio": 0.25, "reset_at": "2099-01-01T05:00:00.123456789Z"},
  # Epoch seconds, as a string.
  "limit_7d": {"used_ratio": 0.625, "reset_at": "4070908800"},
  "limit_month_total": {"used_ratio": 1.5, "reset_at": "2099-02-01T00:00:00Z"},
  "limit_month_code": {"used_ratio": "0.5", "resetTime": "2099-03-01T00:00:00Z"},
}})]


def setup(home, bin):
  kimi = home / ".kimi-code"
  (kimi / "credentials").mkdir(parents=True, exist_ok=True)
  (kimi / "credentials/kimi-code.json").write_text(json.dumps({
    "access_token": TOKEN, "refresh_token": "kimi-FAKE-REFRESH", "expires_at": time.time() + 3600, "token_type": "Bearer", "scope": "kimi-code",
  }))
  (kimi / "config.toml").write_text(CONFIG)
  for session, records in SESSIONS.items():
    wire = kimi / "sessions/workspace" / session / "agents/main/wire.jsonl"
    wire.parent.mkdir(parents=True, exist_ok=True)
    wire.write_text("".join(json.dumps(record) + "\n" for record in records))


def check(record, requests):
  assert record["ready"] is True, "not ready"
  assert [r["url"] for r in requests] == ["https://api.kimi.com/coding/v1/usages"], requests
  assert requests[0]["headers"]["authorization"] == "Bearer " + TOKEN, "the token was not sent"
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.25, "resetsAt": "2099-01-01T05:00:00.123456Z"},
    {"label": "Weekly limit", "percent": 0.625, "resetsAt": "2099-01-01T00:00:00Z"},
    {"label": "Monthly total", "percent": 1.0, "resetsAt": "2099-02-01T00:00:00Z"},
    {"label": "Monthly code", "title": "Code Monthly", "percent": 0.5, "resetsAt": "2099-03-01T00:00:00Z"},
  ], record["limits"]
  assert record["limitsStale"] is False and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limitsStale"], record["usageStatusText"], record["authHelpText"])
  assert record["limitsFetchedAt"] > 0, "no fetch time"

  assert record["hasLocalStats"] is True, "no local stats"
  # The fork's copies of today's first records are not counted again.
  assert record["modelUsage"] == {
    MANAGED: {"inputTokens": 120, "outputTokens": 60, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 10},
    "moonshot/kimi-k2": {"inputTokens": 7, "outputTokens": 3, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"]) == (2, 3), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (1, 2), (record["todaySessions"], record["totalSessions"])
  assert record["todayTotalTokens"] == 390 and record["todayTokensByModel"] == {MANAGED: 390}, (record["todayTotalTokens"], record["todayTokensByModel"])
  days = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {days[-1]: 390, days[-2]: 10}.get(d, 0)} for d in days], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == days[-2:], record["activeDates"]
