# SPDX-License-Identifier: GPL-3.0-only
# A machine where the Copilot CLI has been used (its session store has billed
# requests, one of them to a custom provider) and `gh` is signed in to GitHub
# with no token in the environment, so the quota is asked with what
# `gh auth token` hands over.

import hashlib
import json
import sqlite3
import stat
import time
from datetime import datetime, timedelta, timezone

LOG = HOME = None
NOW = datetime.now(timezone.utc)
TODAY = NOW.astimezone().date().isoformat()
OLD = NOW - timedelta(days=40)
# GitHub's reset is the first of next month, UTC.
RESET = datetime(NOW.year + (NOW.month == 12), NOW.month % 12 + 1, 1, tzinfo=timezone.utc)

ROUTES = [("api.github.com/copilot_internal/user", {
  "login": "octo-FAKE",
  "copilot_plan": "individual_pro",
  "quota_reset_date_utc": RESET.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
  "quota_snapshots": {
    # Not the meter: only premium_interactions is the monthly allowance.
    "chat": {"entitlement": 1000, "remaining": 0, "unlimited": False},
    "premium_interactions": {"entitlement": 1500, "remaining": 1125, "unlimited": False},
  },
})]

GH = '''#!/usr/bin/python3
import sys
open(%r, "a").write(" ".join(sys.argv[1:]) + "\\n")
if sys.argv[1:] == ["auth", "token", "--hostname", "github.com"]:
  print("gho_FAKE-copilot-token")
else:
  sys.exit(1)
'''

# A store from a current CLI: who started each request, and GitHub's own usage
# report on the ones it served.
SCHEMA = (
  "CREATE TABLE assistant_usage_events (session_id TEXT, model TEXT, created_at TEXT, total_nano_aiu INTEGER,"
  " input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER,"
  " initiator TEXT, agent_id TEXT, copilot_usage_model TEXT)"
)


def setup(home, bin):
  global LOG, HOME
  LOG, HOME = home / "gh-calls.log", home
  gh = bin / "gh"
  gh.write_text(GH % str(LOG))
  gh.chmod(gh.stat().st_mode | stat.S_IXUSR)

  hosts = home / ".config" / "gh"
  hosts.mkdir(parents=True)
  (hosts / "hosts.yml").write_text(
    "ghe.example.com:\n    user: enterprise-FAKE\n"
    "github.com:\n    users:\n        octo-FAKE:\n    git_protocol: https\n    user: octo-FAKE\n"
  )

  copilot = home / ".copilot"
  copilot.mkdir()
  today, old = NOW.strftime("%Y-%m-%dT%H:%M:%S.000Z"), OLD.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  conn = sqlite3.connect(copilot / "session-store.db")
  conn.execute(SCHEMA)
  conn.executemany("INSERT INTO assistant_usage_events VALUES (?,?,?,?,?,?,?,?,?,?,?)", [
    # A typed prompt: 10000 tokens in, of which 6000 were read from and 1000 written to the cache.
    ("s1", "claude-sonnet-4.5", today, 2_500_000_000, 10000, 500, 6000, 1000, "user", None, "claude-sonnet-4.5"),
    # The agent's own follow-up call in that session.
    ("s1", "claude-sonnet-4.5", today, 1_000_000_000, 4000, 200, 0, 0, "agent", None, "claude-sonnet-4.5"),
    # Typed, but answered by a subagent: no prompt of its own.
    ("s1", "gpt-5-mini", today, 100_000_000, 100, 10, 0, 0, "user", "sub-FAKE-1", "gpt-5-mini"),
    ("s2", "gpt-5", today, 500_000_000, 2000, 300, 0, 0, "user", None, "gpt-5"),
    # Sent to a custom provider: GitHub reported nothing, so Copilot did not bill it.
    ("s3", "custom-model", today, None, 99999, 9999, 0, 0, "user", None, None),
    ("s0", "claude-sonnet-4.5", old, 9_000_000_000, 1000, 100, 0, 0, "user", None, "claude-sonnet-4.5"),
  ])
  conn.commit()
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True and record["hasPromptStats"] is True
  assert record["tierLabel"] == "Pro+", record["tierLabel"]
  assert len(record["limits"]) == 1, record["limits"]
  meter = record["limits"][0]
  # 1500 entitlement less 1125 remaining is 375 used.
  assert meter["label"] == "Monthly allowance" and meter["percent"] == 0.25, meter
  assert meter["resetsAt"] and datetime.fromisoformat(meter["resetsAt"]) == RESET, meter["resetsAt"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000, record["limitsFetchedAt"]
  assert "retryAdvised" not in record

  assert [r["url"] for r in requests] == ["https://api.github.com/copilot_internal/user"], requests
  headers = requests[0]["headers"]
  assert headers["authorization"] == "Bearer gho_FAKE-copilot-token", "the token gh handed over was not sent"
  assert headers["accept"] == "application/json" and headers["user-agent"] == "cachyos-agent-usage", headers
  assert LOG.read_text().splitlines() == ["auth token --hostname github.com"], LOG.read_text()
  # The answer is kept for the account hosts.yml names for github.com, not the Enterprise one above it.
  digest = hashlib.sha256(b"gh:github.com:octo-FAKE").hexdigest()[:16]
  cache = HOME / ".cache" / "cachyos-agent" / "usage" / f"copilot-limits-{digest}.json"
  assert cache.is_file(), "the allowance was not kept for the account gh is signed in as"
  kept = json.loads(cache.read_text())
  assert kept["entitlement"] == 1500 and kept["used"] == 375 and kept["planLabel"] == "Pro+", kept

  # Three typed prompts (the agent's call and the subagent's are none), in three sessions
  # (the custom provider's s3 is not one); two of the prompts and two sessions today.
  assert record["totalPrompts"] == 3 and record["totalSessions"] == 3, (record["totalPrompts"], record["totalSessions"])
  assert record["todayPrompts"] == 2 and record["todaySessions"] == 2
  assert record["todayTotalTokens"] == 17110, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"claude-sonnet-4.5": 14700, "gpt-5-mini": 110, "gpt-5": 2300}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    # Cache reads and writes come off the input, so the buckets do not overlap.
    "claude-sonnet-4.5": {"inputTokens": 8000, "outputTokens": 800, "cacheReadInputTokens": 6000, "cacheCreationInputTokens": 1000},
    "gpt-5-mini": {"inputTokens": 100, "outputTokens": 10, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
    "gpt-5": {"inputTokens": 2000, "outputTokens": 300, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["activeDays"] == 2 and record["activeDates"] == [OLD.astimezone().date().isoformat(), TODAY], record["activeDates"]
  days = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert days[TODAY] == 17110 and sum(days.values()) == 17110, days
