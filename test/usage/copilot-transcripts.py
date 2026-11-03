# SPDX-License-Identifier: GPL-3.0-only
# A machine with an older Copilot CLI (no session store, only the transcripts
# of its sessions) and no GitHub sign-in anywhere, with a monthlyCredits
# budget in copilot.json: nothing to ask GitHub with, so the meter is an
# estimate from this machine's own spend.

import json
from datetime import datetime, timedelta, timezone

NOW = datetime.now(timezone.utc)
OLD = NOW - timedelta(days=40)
TODAY = NOW.astimezone().date().isoformat()
NEXT_MONTH = datetime(NOW.year + (NOW.month == 12), NOW.month % 12 + 1, 1, tzinfo=timezone.utc)


def events(*rows, when=NOW):
  stamp = when.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  return "".join(json.dumps({"type": kind, "timestamp": stamp, "data": data}) + "\n" for kind, data in rows)


def shutdown(prompt, output, read, write, nano):
  usage = {"inputTokens": prompt, "outputTokens": output, "cacheReadTokens": read, "cacheWriteTokens": write}
  return ("session.shutdown", {"modelMetrics": {"claude-sonnet-4.5": {"usage": usage, "totalNanoAiu": nano}}})


def setup(home, bin):
  config = home / ".config" / "cachyos-agent"
  config.mkdir(parents=True)
  (config / "copilot.json").write_text(json.dumps({"monthlyCredits": 10}))

  sessions = home / ".copilot" / "session-state"
  (sessions / "sess-FAKE-1").mkdir(parents=True)
  (sessions / "sess-FAKE-2").mkdir()
  (sessions / "sess-FAKE-3").mkdir()
  # One session resumed once: the second shutdown's totals include the first's, so
  # the second segment spent the difference. A skill's message is no prompt.
  (sessions / "sess-FAKE-1" / "events.jsonl").write_text(events(
    ("user.message", {"content": "FAKE prompt"}),
    ("user.message", {"content": "FAKE skill text", "source": "skill"}),
    ("assistant.message", {"model": "claude-sonnet-4.5", "outputTokens": 300}),
    ("assistant.message", {"model": "claude-sonnet-4.5", "outputTokens": 100}),
    shutdown(12000, 400, 8000, 1000, 2_000_000_000),
    ("user.message", {"content": "FAKE prompt"}),
    ("assistant.message", {"model": "claude-sonnet-4.5", "outputTokens": 50}),
    shutdown(15000, 450, 9000, 1000, 2_500_000_000),
  ))
  # Still running: no shutdown yet, so only the replies' output is known.
  (sessions / "sess-FAKE-2" / "events.jsonl").write_text(events(
    ("user.message", {"content": "FAKE prompt"}),
    ("assistant.message", {"model": "gpt-5", "outputTokens": 70}),
  ))
  # Spent in an earlier month: its tokens count, its 4 credits are no part of this month's.
  (sessions / "sess-FAKE-3" / "events.jsonl").write_text(events(
    ("user.message", {"content": "FAKE prompt"}),
    ("assistant.message", {"model": "claude-sonnet-4.5", "outputTokens": 20}),
    shutdown(2000, 20, 0, 0, 4_000_000_000),
    when=OLD,
  ))


def check(record, requests):
  assert requests == [], "there is no token to ask GitHub with"
  assert record["ready"] is True and record["hasLocalStats"] is True and record["hasPromptStats"] is True
  assert record["usageStatusText"] == "Waiting for auth", record["usageStatusText"]
  assert record["authHelpText"] == "Run `gh auth login`, or set COPILOT_QUOTA_TOKEN, to show Copilot's monthly allowance.", record["authHelpText"]
  assert record["tierLabel"] == ""
  # 2.5 AI credits spent this month of the 10 budgeted.
  assert record["limits"] == [{"label": "Monthly allowance (est.)", "percent": 0.25, "resetsAt": NEXT_MONTH.isoformat()}], record["limits"]
  assert record["limitsStale"] is False and record["limitsFetchedAt"] == 0

  assert record["totalPrompts"] == 4 and record["totalSessions"] == 3 and record["todayPrompts"] == 3 and record["todaySessions"] == 2
  assert record["modelUsage"] == {
    "claude-sonnet-4.5": {"inputTokens": 7000, "outputTokens": 470, "cacheReadInputTokens": 9000, "cacheCreationInputTokens": 1000},
    "gpt-5": {"inputTokens": 0, "outputTokens": 70, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 15520 and record["todayTokensByModel"] == {"claude-sonnet-4.5": 15450, "gpt-5": 70}, record["todayTokensByModel"]
  assert record["activeDays"] == 2 and record["activeDates"] == [OLD.astimezone().date().isoformat(), TODAY], record["activeDates"]
