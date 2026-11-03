# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Muse (`muse login`) on a subscription: auth.json under
# ~/.config/muse, the CLI's session logs and its session index under
# ~/.local/share/muse, and a key service that answers with the plan and both windows.

import json
import sqlite3
import time
from datetime import datetime, timedelta

NOW = datetime.now().astimezone()
TODAY = NOW.date().isoformat()
EARLIER = (NOW - timedelta(days=3)).date().isoformat()

ROUTES = [("api.meta.ai/muse-code/key", {
  "api_key": "FAKE-muse-api-key",
  "is_subs_active": True,
  "subs_tier_name": "Muse Plus",
  "subs_usage": {
    "window": {"used_percent": 37.5, "window_duration_mins": 300, "resets_at": 4070912400},
    "weekly": {"used_percent": 12, "window_duration_mins": 10080, "resets_at": 4071513600},
  },
})]


def micros(moment):
  return int(moment.timestamp() * 1_000_000)


def log(*events):
  """A session log: a line per event, its recorded_at in microseconds and its id."""
  return "".join(json.dumps({"recorded_at": micros(NOW), "id": event_id, "payload": payload}) + "\n" for event_id, payload in events)


def metadata(model):
  return ("meta-" + model, {"kind": "metadata", "record": {"model_id": model}})


def completed(event_id, usage, model=None):
  event = {"kind": "model_completed", "usage": usage}
  if model:
    event["model"] = model
  return (event_id, {"event": event})


def setup(home, bin):
  config = home / ".config" / "muse"
  config.mkdir(parents=True)
  (config / "auth.json").write_text(json.dumps({"providers": {"meta": {"access_token": "muse-FAKE-token"}}}))

  data = home / ".local" / "share" / "muse"
  for session in ("sess-FAKE-1", "sess-FAKE-2"):
    (data / "sessions" / session).mkdir(parents=True)
  # The first session names its model once; its second completion names another, and
  # a completion repeated under the same id is a copy of one already counted.
  first = completed("e1", {"input_tokens": 5000, "output_tokens": 800, "cache_read_tokens": 3000, "cache_write_tokens": 500})
  (data / "sessions" / "sess-FAKE-1" / "session.jsonl").write_text(log(
    metadata("meta/muse-spark-1.3"),
    first,
    first,
    completed("e2", {"input_tokens": 2000, "output_tokens": 100, "cached_tokens": 500}, "meta/muse-spark-1.2"),
  ))
  (data / "sessions" / "sess-FAKE-2" / "session.jsonl").write_text(log(
    metadata("muse-spark-1.3"),
    completed("e3", {"input_tokens": 1000, "output_tokens": 200}),
  ))

  # The index knows the first session (3 prompts, begun today) and one that has no log
  # left (5 prompts, begun three days ago); the second session is not in it yet.
  conn = sqlite3.connect(data / "session-index.db")
  conn.execute("CREATE TABLE sessions (session_id TEXT, created_at_us INTEGER, prompt_count INTEGER)")
  conn.executemany("INSERT INTO sessions VALUES (?,?,?)", [
    ("sess-FAKE-1", micros(NOW), 3),
    ("sess-FAKE-gone", micros(NOW - timedelta(days=3)), 5),
  ])
  conn.commit()
  conn.close()


def check(record, requests):
  assert record["ready"] is True and record["hasLocalStats"] is True and record["hasPromptStats"] is True
  assert record["tierLabel"] == "Muse Plus", record["tierLabel"]
  assert record["limits"] == [
    {"label": "Session (5-hour)", "percent": 0.375, "resetsAt": "2099-01-01T01:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 0.12, "resetsAt": "2099-01-08T00:00:00+00:00"},
  ], record["limits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000, record["limitsFetchedAt"]
  assert "retryAdvised" not in record

  assert [r["url"] for r in requests] == ["https://api.meta.ai/muse-code/key"], requests
  assert requests[0]["method"] == "POST" and requests[0]["body"] == b"{}", requests[0]
  assert requests[0]["headers"]["authorization"] == "Bearer muse-FAKE-token", "the saved sign-in was not sent"

  # Prompts: the index's 3 and 5, and the second session's one completion, which the
  # index has no row for. Sessions: those three. Today: the first session's 3 and that one.
  assert record["totalPrompts"] == 9 and record["totalSessions"] == 3, (record["totalPrompts"], record["totalSessions"])
  assert record["todayPrompts"] == 4 and record["todaySessions"] == 2, (record["todayPrompts"], record["todaySessions"])
  assert record["todayTotalTokens"] == 9100, record["todayTotalTokens"]
  assert record["todayTokensByModel"] == {"muse-spark-1.3": 7000, "muse-spark-1.2": 2100}, record["todayTokensByModel"]
  assert record["modelUsage"] == {
    # Cached tokens come off the input; the repeated e1 counts once.
    "muse-spark-1.3": {"inputTokens": 2500, "outputTokens": 1000, "cacheReadInputTokens": 3000, "cacheCreationInputTokens": 500},
    "muse-spark-1.2": {"inputTokens": 1500, "outputTokens": 100, "cacheReadInputTokens": 500, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["activeDays"] == 2 and record["activeDates"] == [EARLIER, TODAY], record["activeDates"]
  days = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert days[TODAY] == 9100 and sum(days.values()) == 9100, days
