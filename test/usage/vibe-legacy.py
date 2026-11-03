# SPDX-License-Identifier: GPL-3.0-only
# A machine with sessions from an older Mistral Vibe, never asked for its plan:
# per-session meta.json files with running totals under a save_dir and prefix
# that config.toml moved. A session and its subagent today, a session on a
# Mistral-backend provider with no api_base yesterday, one on a llama.cpp
# server on this machine, and a folder the prefix does not name.

import json
from datetime import date, datetime, timedelta

CONFIG = """\
[session_logging]
save_dir = "{save_dir}"
session_prefix = "chat"
"""


def when(days_ago, hour=9):
  return (datetime.combine(date.today() - timedelta(days=days_ago), datetime.min.time()) + timedelta(hours=hour)).astimezone().isoformat()


def meta(days_ago, models, providers, active, prompt_tokens, cached, completion):
  return {
    "start_time": when(days_ago),
    "config": {"active_model": active, "models": models, "providers": providers},
    "stats": {"session_prompt_tokens": prompt_tokens, "session_cached_tokens": cached, "session_completion_tokens": completion},
  }


def session(root, document, messages=None):
  root.mkdir(parents=True)
  (root / "meta.json").write_text(json.dumps(document))
  if messages is not None:
    (root / "messages.jsonl").write_text("".join(json.dumps(message) + "\n" for message in messages))


def setup(home, bin):
  saved = home / "vibe-sessions"
  vibe = home / ".vibe"
  vibe.mkdir()
  (vibe / "config.toml").write_text(CONFIG.format(save_dir=saved))

  # No alias, so the model is named by its id, less its path and thinking level.
  mistral = [{"name": "mistralai/devstral-small-2:high", "provider": "mistral"}]
  api = [{"name": "mistral", "api_base": "https://api.mistral.ai/v1", "backend": "mistral"}]
  typed = {"role": "user", "content": "fix the build"}
  session(saved / "chat_a1", meta(0, mistral, api, "mistralai/devstral-small-2:high", 8000, 3000, 900), [
    {"role": "system", "content": "You are Vibe"},
    typed,
    # Vibe's own turns are no prompts.
    {"role": "user", "content": "<reminder>", "injected": True},
    {"role": "assistant", "content": "done"},
    typed,
    {"role": "user", "content": "summary", "context_boundary": True},
    typed,
  ])
  # A subagent's totals count toward its session; its messages are not typed prompts.
  session(saved / "chat_a1" / "agents" / "sub1", meta(0, mistral, api, "mistralai/devstral-small-2:high", 2000, 500, 100), [typed, typed])
  # A mistral backend with no api_base is Mistral's API.
  eu = [{"name": "mistral-eu", "backend": "mistral"}]
  session(saved / "chat_c3", meta(1, [{"name": "mistral-medium-latest", "provider": "mistral-eu"}], eu, "mistral-medium-latest", 3000, 0, 400))
  local = [{"name": "llamacpp", "api_base": "http://127.0.0.1:8080/v1"}]
  session(saved / "chat_b2", meta(1, [{"name": "qwen3-coder", "provider": "llamacpp"}], local, "qwen3-coder", 90000, 0, 9000), [typed])
  session(saved / "session_z9", meta(0, mistral, api, "mistralai/devstral-small-2:high", 70000, 0, 7000), [typed])


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  # Vibe never cached a whoami answer: the plan is unnamed, and that is no trouble.
  assert record["tierLabel"] == "" and record["limits"] == [] and record["usageStatusText"] == "", (record["tierLabel"], record["limits"], record["usageStatusText"])

  today, yesterday = date.today(), date.today() - timedelta(days=1)
  assert record["totalPrompts"] == 3 and record["todayPrompts"] == 3, (record["totalPrompts"], record["todayPrompts"])
  assert record["totalSessions"] == 2 and record["todaySessions"] == 1, (record["totalSessions"], record["todaySessions"])
  assert record["modelUsage"] == {
    "devstral-small-2": {"inputTokens": 6500, "outputTokens": 1000, "cacheReadInputTokens": 3500, "cacheCreationInputTokens": 0},
    "mistral-medium-latest": {"inputTokens": 3000, "outputTokens": 400, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 11000 and record["todayTokensByModel"] == {"devstral-small-2": 11000}, (record["todayTotalTokens"], record["todayTokensByModel"])
  tokens = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert tokens[today.isoformat()] == 11000 and tokens[yesterday.isoformat()] == 3400 and sum(tokens.values()) == 14400, tokens
  assert record["activeDays"] == 2 and record["activeDates"] == [yesterday.isoformat(), today.isoformat()], (record["activeDays"], record["activeDates"])
