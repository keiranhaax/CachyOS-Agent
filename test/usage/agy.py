# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Antigravity (agy) with a Google AI Pro account, the
# sign-in in the Secret Service keyring. It holds three conversations (one of
# them spawned a subagent) with transcripts in both of Gemini's step shapes,
# and Google's quota answers for the Gemini group and two scoped groups.

import base64
import hashlib
import json
import os
import sqlite3
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

ACCESS = "ya29.FAKE-AGY-ACCESS"
EMAIL = "fake.user@example.test"
ENV = {"CLOUD_CODE_URL": "https://cloudcode.fake.test/"}
BASE = "https://cloudcode.fake.test/v1internal:"


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()

  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def noon(days_ago):
  return datetime.combine(date.today() - timedelta(days=days_ago), time(12))


def ms(moment):
  return int(moment.timestamp() * 1000)


def zulu(moment):
  return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# What `secret-tool lookup service gemini username antigravity` prints. The
# stub answers only to that lookup, so a collector asking for anything else
# finds no sign-in.
SIGN_IN = {
  "token": {"access_token": ACCESS, "refresh_token": "1//FAKE-AGY-REFRESH", "expiry": "2099-01-01T00:00:00Z"},
  "auth_method": "consumer",
  "id_token": jwt({"email": EMAIL}),
}
SECRET_TOOL = f"""#!/usr/bin/python3
import sys
if sys.argv[1:] != ["lookup", "service", "gemini", "username", "antigravity"]:
  sys.exit(1)
print({json.dumps(SIGN_IN)!r})
"""

# The Claude and GPT group comes first, so the Gemini group is found by its
# name and not by its place. Its 5-hour bucket is touched, its weekly one is
# not (an untouched scoped bucket is left out), a third group with a name of
# its own is shown under that name, and a fourth lists no buckets.
ROUTES = [
  (BASE + "loadCodeAssist", {
    "currentTier": {"id": "free-tier", "name": "Gemini Code Assist for individuals"},
    "paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro for Antigravity"},
    "cloudaicompanionProject": "fake-project-123",
  }),
  (BASE + "retrieveUserQuotaSummary", {"groups": [
    {"displayName": "Claude and open-source models", "buckets": [
      {"bucketId": "scoped-a", "window": "5h", "remainingFraction": 0.9, "resetTime": "2099-03-01T05:00:00Z"},
      {"bucketId": "scoped-b", "window": "weekly", "remainingFraction": 1.0, "resetTime": "2099-03-07T00:00:00Z"},
    ]},
    {"displayName": "Gemini models", "buckets": [
      {"bucketId": "pool-a", "window": "5h", "remainingFraction": 0.8, "resetTime": "2099-01-01T05:00:00Z"},
      {"bucketId": "pool-b", "window": "weekly", "remainingFraction": 0.35, "resetTime": "2099-01-07T00:00:00Z"},
    ]},
    {"displayName": "GPT-OSS", "buckets": [
      {"bucketId": "pool-c", "window": "WEEKLY", "remainingFraction": 0.75, "resetTime": "2099-02-07T00:00:00Z"},
    ]},
    # A group that lists no buckets at all has nothing to show.
    {"displayName": "Empty models"},
  ]}),
]


def step(**fields):
  return json.dumps(fields)


def setup(home, bin):
  tool = bin / "secret-tool"
  tool.write_text(SECRET_TOOL)
  tool.chmod(0o755)

  root = home / ".gemini" / "antigravity-cli"
  (root / "brain" / "conv-1" / ".system_generated" / "logs").mkdir(parents=True, exist_ok=True)
  # Every way a prompt is dated and tied to its conversation: epoch ms with
  # conversationId, ISO text with conversation_id, sessionId, a subagent's own
  # id, epoch seconds, and epoch seconds as text with no conversation. A row
  # with no usable time (0, or a stray 1 that reads as 1970) is no prompt, and
  # a line that is no object is no row.
  (root / "history.jsonl").write_text("\n".join([
    json.dumps({"timestamp": ms(noon(0)), "conversationId": "conv-1"}),
    json.dumps({"timestamp": zulu(noon(0) + timedelta(minutes=5)), "conversation_id": "conv-snake"}),
    json.dumps({"timestamp": ms(noon(0) + timedelta(minutes=8)), "sessionId": "conv-sid"}),
    json.dumps({"timestamp": ms(noon(0) + timedelta(minutes=10)), "conversationId": "conv-sub"}),
    json.dumps({"timestamp": int(noon(2).timestamp()), "conversationId": "conv-2"}),
    json.dumps({"timestamp": str(int(noon(3).timestamp()))}),
    json.dumps({"timestamp": 0, "conversationId": "conv-bad"}),
    json.dumps({"timestamp": 1, "conversationId": "conv-stale"}),
    "this line is not JSON",
    "[1, 2]",
  ]) + "\n")

  # A conversation points at the one that spawned it, and two that point at
  # each other still end somewhere.
  database = root / "conversation_summaries.db"
  database.unlink(missing_ok=True)
  conn = sqlite3.connect(database)
  with conn:
    conn.execute("CREATE TABLE conversation_summaries (conversation_id TEXT, last_modified_time TEXT, parent_conversation_id TEXT)")
    conn.executemany("INSERT INTO conversation_summaries VALUES (?, ?, ?)", [
      ("conv-1", zulu(noon(0)), None),
      ("conv-sub", zulu(noon(0)), "conv-1"),
      ("conv-2", zulu(noon(2)), None),
      # Touched today with no prompt in the history: a session all the same.
      ("conv-3", zulu(noon(0)), None),
      ("conv-loop-a", zulu(noon(5)), "conv-loop-b"),
      ("conv-loop-b", zulu(noon(5)), "conv-loop-a"),
    ])
  conn.close()

  # The model carries from step to step until a step names another one: the
  # picker's name for it, or the model's own id in either spelling. Gemini's
  # prompt count includes the cached part (and the cache can't exceed it);
  # the newer shape counts input apart from the cache. Before any model is
  # named, a step's tokens are an unknown model's.
  (root / "brain" / "conv-1" / ".system_generated" / "logs" / "transcript.jsonl").write_text("\n".join([
    step(created_at=zulu(noon(0)), usage={"prompt_token_count": 50, "candidates_token_count": 5}),
    step(content="Switched `Model Selection` from Gemini 3 Pro to Gemini 3.8 Flash (High). Done."),
    step(created_at=zulu(noon(0)), usage={"prompt_token_count": 1000, "cached_content_token_count": 400, "candidates_token_count": 200, "thoughts_token_count": 50}),
    step(timestamp=ms(noon(0)), model="gemini-3-pro", input_tokens=300, output_tokens=70, cache_read_tokens=20, cache_write_tokens=10),
    step(type="user_input", created_at=zulu(noon(0))),
    step(model="Gemini_3_Pro", usage={"prompt_token_count": 100, "candidates_token_count": 10}),
    step(created_at=zulu(noon(2)), usage={"prompt_token_count": 500, "cached_content_token_count": 600, "candidates_token_count": 40}),
    step(created_at=zulu(noon(2)), model="Claude Sonnet 4.5 - Thinking", usage={"prompt_token_count": 70, "candidates_token_count": 7}),
    "this line is not JSON",
  ]) + "\n")


def check(record, requests):
  assert record["ready"] is True and record["tierLabel"] == "Pro", (record["ready"], record["tierLabel"])
  assert record["limits"] == [
    {"label": "Session (5-hour)", "title": "Session", "percent": 0.2, "resetsAt": "2099-01-01T05:00:00+00:00"},
    {"label": "Weekly (7-day)", "title": "Weekly", "percent": 0.65, "resetsAt": "2099-01-07T00:00:00+00:00"},
    {"label": "Claude/GPT Session", "title": "Claude/GPT Session", "percent": 0.1, "resetsAt": "2099-03-01T05:00:00+00:00"},
    {"label": "GPT-OSS Weekly", "title": "GPT-OSS Weekly", "percent": 0.25, "resetsAt": "2099-02-07T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == "", (record["usageStatusText"], record["authHelpText"])
  assert record["limitsStale"] is False and record["retryAdvised"] is False

  # The plan is asked first and names the project the quota is asked for.
  assert [(r["method"], r["url"]) for r in requests] == [("POST", BASE + "loadCodeAssist"), ("POST", BASE + "retrieveUserQuotaSummary")], requests
  assert [json.loads(r["body"]) for r in requests] == [{}, {"project": "fake-project-123"}], [r["body"] for r in requests]
  for request in requests:
    assert request["headers"]["authorization"] == "Bearer " + ACCESS, "the sign-in was not sent"
    assert request["headers"]["content-type"] == "application/json" and request["headers"]["user-agent"] == "antigravity", request["headers"]

  # The answer is kept under the account's email, for the next failed check.
  digest = hashlib.sha256(EMAIL.encode()).hexdigest()[:16]
  kept = json.loads((Path(os.environ["XDG_CACHE_HOME"]) / "cachyos-agent" / "usage" / f"agy-limits-{digest}.json").read_text())
  assert kept["limits"] == record["limits"] and kept["tierLabel"] == "Pro", kept
  assert kept["fetchedAtMs"] == record["limitsFetchedAt"] > 0, (kept["fetchedAtMs"], record["limitsFetchedAt"])

  days = [(date.today() - timedelta(days=n)).isoformat() for n in range(6, -1, -1)]
  assert record["hasLocalStats"] is True and record["hasPromptStats"] is True
  # conv-sub is part of conv-1, conv-3 is a session with no prompt, and the two
  # conversations that name each other are one session each.
  assert (record["todayPrompts"], record["totalPrompts"]) == (4, 6), (record["todayPrompts"], record["totalPrompts"])
  assert (record["todaySessions"], record["totalSessions"]) == (4, 7), (record["todaySessions"], record["totalSessions"])
  assert record["modelUsage"] == {
    "unknown": {"inputTokens": 50, "outputTokens": 5, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
    "gemini-3.8-flash-high": {"inputTokens": 600, "outputTokens": 250, "cacheReadInputTokens": 400, "cacheCreationInputTokens": 0},
    "gemini-3-pro": {"inputTokens": 400, "outputTokens": 120, "cacheReadInputTokens": 520, "cacheCreationInputTokens": 10},
    "claude-sonnet-4.5-thinking": {"inputTokens": 70, "outputTokens": 7, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 1705 and record["todayTokensByModel"] == {"unknown": 55, "gemini-3.8-flash-high": 1250, "gemini-3-pro": 400}, record["todayTokensByModel"]
  # The step with no date counts toward the totals and no day.
  assert record["recentDays"] == [{"date": day, "messageCount": {days[6]: 1705, days[4]: 617}.get(day, 0)} for day in days], record["recentDays"]
  assert record["activeDays"] == 3 and record["activeDates"] == [days[3], days[4], days[6]], record["activeDates"]
