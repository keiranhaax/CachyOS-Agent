# SPDX-License-Identifier: GPL-3.0-only
# A machine where Antigravity is signed in only through opencode's
# Antigravity plugin (its accounts file, and a sign-in under opencode's
# "google" provider), with opencode answers through the plugin today and
# yesterday, a Gemini API reply under the same provider that is not
# Antigravity's, and an Anthropic reply that only looks like it.

import json
import sqlite3
from datetime import datetime, timedelta

ACCESS = "ya29.FAKE-OPENCODE-ACCESS"
BASE = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
NOON = datetime.now().replace(hour=12, minute=0, second=0, microsecond=0)
YESTERDAY = NOON - timedelta(days=1)
DAY = "%Y-%m-%d"


def ms(moment):
  return int(moment.timestamp() * 1000)


def assistant(provider, model, parent, moment, tokens, cache=(0, 0), agent="build"):
  # An opencode message row as the original `message` table keeps it.
  return json.dumps({
    "role": "assistant", "providerID": provider, "modelID": model, "parentID": parent, "agent": agent,
    "time": {"created": ms(moment)},
    "tokens": {"input": tokens[0], "output": tokens[1], "reasoning": tokens[2], "cache": {"read": cache[0], "write": cache[1]}},
  })


MESSAGES = [
  ("ses_a", "msg_a1", assistant("google", "antigravity-gemini-3-pro", "msg_u1", NOON, (100, 50, 25), (10, 5))),
  ("ses_a", "msg_a2", assistant("google", "antigravity-claude-sonnet-4-5", "msg_u2", NOON + timedelta(minutes=1), (20, 10, 0))),
  ("ses_b", "msg_b1", assistant("google", "antigravity-gemini-3-pro", "msg_u3", YESTERDAY, (4, 6, 0))),
  ("ses_c", "msg_c1", assistant("google", "gemini-2.5-pro", "msg_u4", NOON, (700, 700, 0))),
  # Its agent's name starts with google, so a search for the provider finds it; it is still Anthropic's.
  ("ses_c", "msg_c2", assistant("anthropic", "antigravity-claude", "msg_u5", NOON, (800, 800, 0), agent="google-helper")),
]

ROUTES = [
  (BASE + "loadCodeAssist", {"currentTier": {"id": "g1-plus-tier", "name": "Google AI Plus"}}),
  # No group is named for Gemini, so the first one is the plan's. A reset with
  # no zone is UTC, a window's case does not matter, and an amount of zero
  # left is all of it spent.
  (BASE + "retrieveUserQuotaSummary", {"groups": [{"displayName": "Antigravity", "buckets": [
    {"window": "5h", "remainingFraction": 0.5, "resetTime": "2099-05-01T05:00:00"},
    {"window": "Weekly", "remainingAmount": 0, "resetTime": "2099-05-07T00:00:00Z"},
  ]}]}),
]


def setup(home, bin):
  # The plugin's own accounts file is what makes opencode's "google" sign-in count.
  config = home / ".config" / "opencode"
  config.mkdir(parents=True, exist_ok=True)
  (config / "antigravity-accounts.json").write_text(json.dumps({"version": 1, "accounts": []}))
  data = home / ".local" / "share" / "opencode"
  data.mkdir(parents=True, exist_ok=True)
  (data / "auth.json").write_text(json.dumps({"google": {"type": "oauth", "access": ACCESS, "refresh": "1//FAKE-OPENCODE", "expires": 4102444800000}}))
  db = data / "opencode.db"
  db.unlink(missing_ok=True)
  conn = sqlite3.connect(db)
  with conn:
    conn.execute("CREATE TABLE session (id TEXT PRIMARY KEY, time_created INTEGER NOT NULL, parent_id TEXT)")
    conn.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL)")
    for session in ("ses_a", "ses_b", "ses_c"):
      conn.execute("INSERT INTO session VALUES (?, ?, NULL)", (session, ms(YESTERDAY - timedelta(hours=1))))
    conn.executemany("INSERT INTO message VALUES (?, ?, 0, ?)", [(message, session, data) for session, message, data in MESSAGES])
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Plus", (record["ready"], record["tierLabel"])
  assert [r["url"].rsplit(":", 1)[1] for r in requests] == ["loadCodeAssist", "retrieveUserQuotaSummary"], requests
  assert all(r["headers"]["authorization"] == "Bearer " + ACCESS for r in requests), "opencode's sign-in was not sent"
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.5, "resetsAt": "2099-05-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 1.0, "resetsAt": "2099-05-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "" and record["limitsStale"] is False

  assert record["hasLocalStats"] is True
  assert record["modelUsage"] == {
    "antigravity-gemini-3-pro": {"inputTokens": 104, "outputTokens": 81, "cacheReadInputTokens": 10, "cacheCreationInputTokens": 5},
    "antigravity-claude-sonnet-4-5": {"inputTokens": 20, "outputTokens": 10, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"]) == (2, 3), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (1, 2), (record["todaySessions"], record["totalSessions"])
  assert record["todayTotalTokens"] == 220 and record["todayTokensByModel"] == {"antigravity-gemini-3-pro": 190, "antigravity-claude-sonnet-4-5": 30}, record["todayTokensByModel"]
  days = [(NOON - timedelta(days=n)).strftime(DAY) for n in range(6, -1, -1)]
  assert record["recentDays"] == [{"date": d, "messageCount": {days[-1]: 220, days[-2]: 10}.get(d, 0)} for d in days], record["recentDays"]
  assert record["activeDays"] == 2 and record["activeDates"] == days[-2:], record["activeDates"]
