# SPDX-License-Identifier: GPL-3.0-only
# A machine with no Antigravity sign-in that has driven Antigravity from pi
# and from OpenClaw today: each session holds one prompt answered through the
# google-antigravity provider, and pi's also one answered by Anthropic, which
# is not Antigravity's. Reading sessions needs ripgrep, linked in from the
# machine running the test.

import json
from datetime import date, datetime, time

NOON = datetime.combine(date.today(), time(12))
STAMP = NOON.astimezone().strftime("%Y-%m-%dT%H:%M:%S.000Z")


def line(entry_id, role, **message):
  moment = int(NOON.timestamp() * 1000)
  return json.dumps({"type": "message", "id": entry_id, "timestamp": STAMP, "message": {"role": role, "timestamp": moment, **message}}) + "\n"


def reply(entry_id, provider, model, input_tokens, output_tokens, cache=(0, 0)):
  return line(entry_id, "assistant", provider=provider, model=model, responseId="resp-" + entry_id, usage={
    "input": input_tokens, "output": output_tokens, "cacheRead": cache[0], "cacheWrite": cache[1],
  })


NEEDS = ("rg",)


def setup(home, bin):
  pi = home / ".pi" / "agent" / "sessions" / "--fake-project--"
  pi.mkdir(parents=True, exist_ok=True)
  (pi / "session-pi.jsonl").write_text(
    json.dumps({"type": "session", "id": "pi-1", "timestamp": STAMP}) + "\n"
    + line("u1", "user", content="FAKE prompt")
    + reply("a1", "google-antigravity", "Gemini-3-Pro (High)", 100, 50, (10, 5))
    + line("u2", "user", content="FAKE prompt")
    + reply("a2", "anthropic", "claude-sonnet-4-5", 900, 900)
  )
  claw = home / ".openclaw" / "agents" / "main" / "sessions"
  claw.mkdir(parents=True, exist_ok=True)
  (claw / "session-claw.jsonl").write_text(
    json.dumps({"type": "session", "id": "claw-1", "timestamp": STAMP}) + "\n"
    + line("u3", "user", content="FAKE prompt")
    + reply("a3", "google-antigravity", "gemini-3-flash", 30, 20)
  )


def check(record, requests):
  assert requests == [], "the quota was asked for without a sign-in"
  assert record["ready"] is True and record["hasLocalStats"] is True
  assert record["usageStatusText"] == "Waiting for auth" and record["limits"] == []
  assert record["modelUsage"] == {
    "gemini-3-pro-high": {"inputTokens": 100, "outputTokens": 50, "cacheReadInputTokens": 10, "cacheCreationInputTokens": 5},
    "gemini-3-flash": {"inputTokens": 30, "outputTokens": 20, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert (record["todayPrompts"], record["totalPrompts"], record["todaySessions"], record["totalSessions"]) == (2, 2, 2, 2), record
  assert record["todayTotalTokens"] == 215 and record["todayTokensByModel"] == {"gemini-3-pro-high": 165, "gemini-3-flash": 50}, record["todayTokensByModel"]
