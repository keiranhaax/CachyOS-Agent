# SPDX-License-Identifier: GPL-3.0-only
# A machine that runs Qwen Code signed in with Qwen OAuth and no settings:
# four transcripts under ~/.qwen/projects (two sessions today, one yesterday and
# a fork of the first that added one prompt and one reply), beside a ledger.
# Qwen Code is read from local files alone, so no request goes out.

import json
from datetime import date, datetime, time, timedelta, timezone


def iso(days_ago, hour, minute=0):
  local = datetime.combine(date.today() - timedelta(days=days_ago), time(hour, minute))
  return local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def prompt(uuid, session, when, **extra):
  return {"type": "user", "uuid": uuid, "sessionId": session, "timestamp": when, "message": {"role": "user", "parts": [{"text": "do it"}]}, **extra}


def telemetry(name, uuid, session, when, **event):
  return {
    "type": "system", "subtype": "ui_telemetry", "uuid": uuid, "sessionId": session, "timestamp": when,
    "systemPayload": {"uiEvent": {"event.name": "qwen-code." + name, "event.timestamp": when, **event}},
  }


def reply(uuid, session, when, model, auth, tokens, cached=0, output=0, **extra):
  event = {"model": model, "input_token_count": tokens, "output_token_count": output, "cached_content_token_count": cached, **extra}
  return telemetry("api_response", uuid, session, when, **({"auth_type": auth} if auth else {}), **event)


def write(path, records, raw=()):
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text("".join(line + "\n" for line in [*(json.dumps(record) for record in records), *raw]))


OAUTH = "qwen-oauth"
# A fork copies its source's records verbatim, uuid included, and marks each one.
FORK_MARK = {"forkedFrom": {"sessionId": "sess-1"}}


def setup(home, bin):
  chats = home / ".qwen" / "projects" / "-home-user-demo" / "chats"
  # Thinking is already inside a Qwen OAuth reply's output.
  first = reply("r1", "sess-1", iso(0, 10, 1), "qwen3-coder-plus", OAUTH, 1000, cached=300, output=200, thoughts_token_count=50, total_token_count=1250)
  write(chats / "sess-1.jsonl", [prompt("u1", "sess-1", iso(0, 10)), first])
  write(chats / "sess-2.jsonl", [
    prompt("u2", "sess-2", iso(0, 10, 5)),
    reply("r2", "sess-2", iso(0, 10, 6), "qwen3-coder-plus", OAUTH, 2000, output=500),
    prompt("u3", "sess-2", iso(0, 10, 7), subtype="notification"),
    prompt("u4", "sess-2", iso(0, 10, 8), subtype="mid_turn_user_message"),
    telemetry("tool_call", "t1", "sess-2", iso(0, 10, 9), function_name="read_file"),
    # The model is named by the last segment of its id.
    reply("r3", "sess-2", iso(0, 10, 10), "alibaba/qwen3-max", OAUTH, 800, output=150),
  ], raw=["not json {"])
  # A ledger repeats nothing billable, whatever it holds.
  write(chats / "sess-2.ledger.jsonl", [reply("l1", "sess-2", iso(0, 10, 1), "qwen3-coder-plus", OAUTH, 777777, output=777777)])
  write(chats / "sess-3.jsonl", [
    prompt("u5", "sess-3", iso(1, 9)),
    # A transcript from before Qwen Code kept the auth type: Qwen Code's own.
    reply("r4", "sess-3", iso(1, 9, 1), "qwen3-coder-flash", "", 400, output=100),
    prompt("u6", "sess-3", iso(1, 9, 30)),
    # A prompt whose request failed still counts.
    telemetry("api_error", "e1", "sess-3", iso(1, 9, 31), model="qwen3-coder-flash", auth_type=OAUTH),
  ])
  # The fork's file sorts before its source's, yet the source keeps its records.
  write(chats / "a-fork.jsonl", [
    prompt("u1", "sess-fork", iso(0, 10), **FORK_MARK),
    {**first, "sessionId": "sess-fork", **FORK_MARK},
    prompt("u7", "sess-fork", iso(0, 11)),
    reply("r5", "sess-fork", iso(0, 11, 1), "qwen3-coder-plus", OAUTH, 100, output=50),
  ])


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  # Qwen publishes no quota to read: no meters, and nothing waiting on a sign-in.
  assert record["limits"] == [] and record["tierLabel"] == "" and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limits"], record["tierLabel"], record["usageStatusText"], record["authHelpText"])

  today, yesterday = date.today(), date.today() - timedelta(days=1)
  assert record["todayPrompts"] == 4 and record["totalPrompts"] == 6, (record["todayPrompts"], record["totalPrompts"])
  # The fork's copies of u1 and r1 are not counted again and do not take them from sess-1.
  assert record["totalSessions"] == 4 and record["todaySessions"] == 3, (record["totalSessions"], record["todaySessions"])
  assert record["modelUsage"] == {
    "qwen3-coder-plus": {"inputTokens": 2800, "outputTokens": 750, "cacheReadInputTokens": 300, "cacheCreationInputTokens": 0},
    "qwen3-max": {"inputTokens": 800, "outputTokens": 150, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
    "qwen3-coder-flash": {"inputTokens": 400, "outputTokens": 100, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 4800 and record["todayTokensByModel"] == {"qwen3-coder-plus": 3850, "qwen3-max": 950}, (record["todayTotalTokens"], record["todayTokensByModel"])
  tokens = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert tokens[today.isoformat()] == 4800 and tokens[yesterday.isoformat()] == 500 and sum(tokens.values()) == 5300, tokens
  assert record["activeDays"] == 2 and record["activeDates"] == [yesterday.isoformat(), today.isoformat()], (record["activeDays"], record["activeDates"])
