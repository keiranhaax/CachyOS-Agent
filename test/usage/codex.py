# SPDX-License-Identifier: GPL-3.0-only
# A machine signed in to Codex with a ChatGPT Pro account: `codex` on PATH,
# auth.json under ~/.codex, rollouts of its own sessions (and one that ran on a
# local Ollama, which this subscription did not pay for), and an app-server that
# answers account/rateLimits/read with the general bucket and a model's bucket.

import base64
import json
import stat
import time
from datetime import datetime, timedelta

LOG = None
NOW = datetime.now().astimezone()
TODAY = NOW.date().isoformat()
EARLIER = (NOW - timedelta(days=2)).date().isoformat()

WINDOW = {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 4070912400}
WEEKLY = {"usedPercent": 18.5, "windowDurationMins": 10080, "resetsAt": 4071513600}
# The model's bucket comes first in the reply, as the app-server's map may list it.
RATE_LIMITS = {
  "rateLimits": {"limitId": "codex", "primary": WINDOW, "secondary": WEEKLY, "planType": "pro"},
  "rateLimitsByLimitId": {
    "codex_spark": {
      "limitId": "codex_spark",
      "limitName": "GPT-5.3-Codex-Spark",
      "primary": {"usedPercent": 7, "windowDurationMins": 300, "resetsAt": 4070916000},
      "secondary": {"usedPercent": 3, "windowDurationMins": 10080, "resetsAt": 4071600000},
      "planType": "pro",
    },
    "codex": {
      "limitId": "codex",
      "limitName": None,
      "primary": WINDOW,
      "secondary": WEEKLY,
      "planType": "pro",
      "individualLimit": {"limit": 50, "used": 12.5, "resetsAt": 4073328000},
    },
  },
  "rateLimitResetCredits": {"credits": [
    {"status": "available", "expiresAt": 4072500000},
    {"status": "available", "expiresAt": 4072000000},
    {"status": "used", "expiresAt": 4071420000},
  ]},
}

# Answers what the collector sends, logs every frame it gets, and fails any
# other request, so a call the collector should not make shows in the log.
APP_SERVER = '''#!/usr/bin/python3
import json, sys
LOG, LIMITS = %r, json.loads(%r)
log = open(LOG, "a")
log.write(json.dumps({"argv": sys.argv[1:]}) + "\\n")
log.flush()
for raw in sys.stdin:
  message = json.loads(raw)
  log.write(json.dumps(message) + "\\n")
  log.flush()
  if "id" not in message:
    continue
  if message["method"] == "initialize":
    reply = {"id": message["id"], "result": {"userAgent": "codex-FAKE/0.0.0"}}
  elif message["method"] == "account/rateLimits/read":
    reply = {"id": message["id"], "result": LIMITS}
  else:
    reply = {"id": message["id"], "error": {"code": -32601, "message": "unexpected " + message["method"]}}
  # A notification rides in the same write as the reply, as the real one's do.
  sys.stdout.write(json.dumps({"method": "account/rateLimits/updated", "params": {}}) + "\\n" + json.dumps(reply) + "\\n")
  sys.stdout.flush()
'''


def jwt(claims):
  def part(value):
    return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b"=").decode()
  return f"{part({'alg': 'none'})}.{part(claims)}.FAKE-SIGNATURE"


def rollout(thread, provider, model, prompts, requests):
  """A rollout of one session: its meta, then a prompt, a turn naming the model
  and a request per entry of `requests` (when, last-request usage)."""
  rows = [(requests[0][0], "session_meta", {"id": thread, "model_provider": provider, "source": "cli"})]
  rows.append((requests[0][0], "turn_context", {"model": model}))
  total = 0
  for index, (when, last) in enumerate(requests):
    if index < prompts:
      rows.append((when, "event_msg", {"type": "user_message", "message": "FAKE prompt"}))
    total += last["input_tokens"] + last["output_tokens"]
    rows.append((when, "event_msg", {"type": "token_count", "info": {"last_token_usage": last, "total_token_usage": {"total_tokens": total}}}))
  return "".join(json.dumps({"timestamp": when, "type": kind, "payload": payload}) + "\n" for when, kind, payload in rows)


def setup(home, bin):
  global LOG
  LOG = home / "codex-app-server.log"
  stub = bin / "codex"
  stub.write_text(APP_SERVER % (str(LOG), json.dumps(RATE_LIMITS)))
  stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

  codex = home / ".codex"
  codex.mkdir()
  claims = {"https://api.openai.com/auth": {"chatgpt_user_id": "user-FAKE-1"}}
  (codex / "auth.json").write_text(json.dumps({
    "auth_mode": "chatgpt",
    "OPENAI_API_KEY": None,
    "tokens": {"id_token": jwt(claims), "access_token": "FAKE-access", "refresh_token": "FAKE-refresh", "account_id": "acct-FAKE-1"},
  }))

  today, earlier = NOW.isoformat(), (NOW - timedelta(days=2)).isoformat()
  sessions = codex / "sessions" / NOW.strftime("%Y/%m/%d")
  sessions.mkdir(parents=True)
  # Two prompts on three requests today: a request that follows no new prompt is
  # a tool call of the one before, and 400 + 100 of the input was cached.
  (sessions / "rollout-FAKE-A.jsonl").write_text(rollout("thread-FAKE-A", "openai", "gpt-5.3-codex", 2, [
    (today, {"input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 200}),
    (today, {"input_tokens": 500, "cached_input_tokens": 100, "output_tokens": 50}),
    (today, {"input_tokens": 2000, "cached_input_tokens": 0, "output_tokens": 300}),
  ]))
  (sessions / "rollout-FAKE-B.jsonl").write_text(rollout("thread-FAKE-B", "openai", "gpt-5.3-codex-mini", 1, [
    (earlier, {"input_tokens": 800, "cached_input_tokens": 0, "output_tokens": 100}),
  ]))
  (sessions / "rollout-FAKE-C.jsonl").write_text(rollout("thread-FAKE-C", "ollama", "qwen3-coder:30b", 1, [
    (today, {"input_tokens": 90000, "cached_input_tokens": 0, "output_tokens": 9000}),
  ]))


def check(record, requests):
  assert requests == [], "Codex's limits come from the app-server, not the network"
  assert record["ready"] is True and record["hasLocalStats"] is True
  assert record["tierLabel"] == "Pro 200", record["tierLabel"]
  assert record["limits"] == [
    {"label": "5h window", "percent": 0.42, "resetsAt": "2099-01-01T01:00:00+00:00"},
    {"label": "Weekly (7-day)", "percent": 0.185, "resetsAt": "2099-01-08T00:00:00+00:00"},
    {"label": "5h window", "percent": 0.07, "resetsAt": "2099-01-01T02:00:00+00:00", "title": "GPT-5.3-Codex-Spark Session"},
    {"label": "Weekly (7-day)", "percent": 0.03, "resetsAt": "2099-01-09T00:00:00+00:00", "title": "GPT-5.3-Codex-Spark Weekly"},
    {"label": "Spend limit", "percent": 0.25, "resetsAt": "2099-01-29T00:00:00+00:00", "title": "Spend limit"},
  ], record["limits"]
  assert record["resetCredits"] == {"available": 2, "nextExpiresAt": "2099-01-13T15:06:40+00:00"}, record["resetCredits"]
  assert record["usageStatusText"] == "" and record["authHelpText"] == ""
  assert record["limitsStale"] is False and abs(time.time() * 1000 - record["limitsFetchedAt"]) < 60_000, record["limitsFetchedAt"]
  assert "accounts" not in record

  frames = [json.loads(line) for line in LOG.read_text().splitlines()]
  assert frames[0] == {"argv": ["-s", "read-only", "-a", "on-request", "app-server"]}, frames[0]
  assert [frame.get("method") for frame in frames[1:]] == ["initialize", "initialized", "account/rateLimits/read"], frames

  # The Ollama rollout is not this subscription's, so none of its 99000 tokens count.
  assert record["totalPrompts"] == 3 and record["totalSessions"] == 2, (record["totalPrompts"], record["totalSessions"])
  assert record["todayPrompts"] == 2 and record["todaySessions"] == 1
  assert record["todayTotalTokens"] == 4050 and record["todayTokensByModel"] == {"gpt-5.3-codex": 4050}
  assert record["modelUsage"] == {
    "gpt-5.3-codex": {"inputTokens": 3000, "outputTokens": 550, "cacheReadInputTokens": 500, "cacheCreationInputTokens": 0},
    "gpt-5.3-codex-mini": {"inputTokens": 800, "outputTokens": 100, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["activeDays"] == 2 and record["activeDates"] == [EARLIER, TODAY], record["activeDates"]
  days = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert days[TODAY] == 4050 and days[EARLIER] == 900 and sum(days.values()) == 4950, days
