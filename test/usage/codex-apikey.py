# SPDX-License-Identifier: GPL-3.0-only
# A machine where Codex is signed in with an API key (auth_mode "apikey"), which
# bills by the token and has no plan limits: the collector must not start an
# app-server to ask for any, and says why there are none. One rollout of a
# session on the built-in provider gives the local stats.

import json
import stat
from datetime import datetime

NOW = datetime.now().astimezone()
MARKER = None

# An app-server that was started when it should not have been leaves a file.
APP_SERVER = '''#!/usr/bin/python3
import sys
open(%r, "w").write(" ".join(sys.argv[1:]))
sys.exit(1)
'''


def setup(home, bin):
  global MARKER
  MARKER = home / "app-server-was-started"
  stub = bin / "codex"
  stub.write_text(APP_SERVER % str(MARKER))
  stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

  codex = home / ".codex"
  sessions = codex / "sessions" / NOW.strftime("%Y/%m/%d")
  sessions.mkdir(parents=True)
  (codex / "auth.json").write_text(json.dumps({"auth_mode": "apikey", "OPENAI_API_KEY": "sk-FAKE-OPENAI"}))
  rows = [
    {"type": "session_meta", "payload": {"id": "thread-FAKE-A", "model_provider": "openai", "source": "cli"}},
    {"type": "turn_context", "payload": {"model": "gpt-5.3-codex"}},
    {"type": "event_msg", "payload": {"type": "user_message", "message": "FAKE prompt"}},
    {"type": "event_msg", "payload": {"type": "token_count", "info": {
      "last_token_usage": {"input_tokens": 700, "cached_input_tokens": 200, "output_tokens": 90},
      "total_token_usage": {"total_tokens": 790},
    }}},
  ]
  (sessions / "rollout-FAKE-A.jsonl").write_text("".join(json.dumps({"timestamp": NOW.isoformat(), **row}) + "\n" for row in rows))


def check(record, requests):
  assert requests == []
  assert not MARKER.exists(), "an app-server was started for an API-key login, which has no limits to read: " + MARKER.read_text()
  assert record["ready"] is True and record["limits"] == [] and record["tierLabel"] == ""
  assert record["authHelpText"] == "Signed in with an API key, which has no plan limits.", record["authHelpText"]
  assert record["usageStatusText"] == "" and record["limitsStale"] is False
  assert record["totalPrompts"] == 1 and record["totalSessions"] == 1 and record["todayPrompts"] == 1
  assert record["modelUsage"] == {
    "gpt-5.3-codex": {"inputTokens": 500, "outputTokens": 90, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 790
