# SPDX-License-Identifier: GPL-3.0-only
# A machine that runs Qwen Code against several services, with the transcripts
# in a runtimeOutputDir: Alibaba's Model Studio (an OpenAI-compatible route in
# settings.json and an Anthropic endpoint from ~/.qwen/.env), OpenAI,
# DeepSeek and a model server on this machine, and a Qwen OAuth reply. Only
# what Alibaba's services and Qwen OAuth answered is Qwen's; the rest is
# another collector's or nobody's.

import json
from datetime import date, datetime, time, timezone

MODEL_STUDIO = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"


def iso(minute):
  local = datetime.combine(date.today(), time(10, minute))
  return local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def prompt(uuid, minute):
  return {"type": "user", "uuid": uuid, "sessionId": "sess-r", "timestamp": iso(minute), "message": {"role": "user", "parts": [{"text": "go"}]}}


def reply(uuid, minute, model, auth, tokens, output, **extra):
  event = {
    "event.name": "qwen-code.api_response", "event.timestamp": iso(minute), "model": model, "auth_type": auth,
    "input_token_count": tokens, "output_token_count": output, **extra,
  }
  return {
    "type": "system", "subtype": "ui_telemetry", "uuid": uuid, "sessionId": "sess-r", "timestamp": iso(minute),
    "systemPayload": {"uiEvent": event},
  }


def error(uuid, minute, model, auth):
  event = {"event.name": "qwen-code.api_error", "event.timestamp": iso(minute), "model": model, "auth_type": auth}
  return {
    "type": "system", "subtype": "ui_telemetry", "uuid": uuid, "sessionId": "sess-r", "timestamp": iso(minute),
    "systemPayload": {"uiEvent": event},
  }


def setup(home, bin):
  qwen = home / ".qwen"
  qwen.mkdir()
  routes = [("qwen3-coder-plus", MODEL_STUDIO), ("gpt-5-mini", "https://api.openai.com/v1"),
            ("deepseek-v4-flash", "https://api.deepseek.com/v1"), ("llama-local", "http://127.0.0.1:11434/v1")]
  (qwen / "settings.json").write_text(json.dumps({
    "advanced": {"runtimeOutputDir": str(home / "qwen-runtime")},
    "security": {"auth": {"selectedType": "openai"}},
    "model": {"name": "qwen3-coder-plus"},
    "modelProviders": {"openai": [{"id": model, "baseUrl": url} for model, url in routes]},
  }))
  # Where an Anthropic-type model goes when no route names one, as dotenv reads it.
  (qwen / ".env").write_text('export ANTHROPIC_BASE_URL="https://dashscope-intl.aliyuncs.com/api/v2/apps/anthropic" # Model Studio\n')

  chats = home / "qwen-runtime" / "projects" / "-home-user-demo" / "chats"
  chats.mkdir(parents=True)
  records = [
    prompt("p1", 1), reply("r1", 2, "qwen3-coder-plus", "openai", 1200, 300, cached_content_token_count=200, thoughts_token_count=999, total_token_count=1500),
    prompt("p2", 3), reply("r2", 4, "gpt-5-mini", "openai", 5000, 800),
    # An Anthropic-type reply has its thinking added to the output, up to what
    # its total leaves over: 1350 - 900 - 400 = 50, not the 80 reported.
    prompt("p3", 5), reply("r3", 6, "qwen3.5-plus", "anthropic", 900, 400, thoughts_token_count=80, total_token_count=1350),
    prompt("p4", 7), reply("r4", 8, "deepseek-v4-flash", "openai", 6000, 900),
    prompt("p5", 9), reply("r5", 10, "qwen3-coder-plus", "qwen-oauth", 500, 100),
    prompt("p6", 11), reply("r6", 12, "llama-local", "openai", 7000, 1000),
    # A request that failed was sent where its error says, not where settings.json selects.
    prompt("p7", 13), error("e1", 14, "gpt-5-mini", "openai"),
    # No reply yet: the prompt goes where settings.json sends the selected model.
    prompt("p8", 15),
  ]
  (chats / "sess-r.jsonl").write_text("".join(json.dumps(record) + "\n" for record in records))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["modelUsage"] == {
    "qwen3-coder-plus": {"inputTokens": 1500, "outputTokens": 400, "cacheReadInputTokens": 200, "cacheCreationInputTokens": 0},
    "qwen3.5-plus": {"inputTokens": 900, "outputTokens": 450, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 3450 and record["todayTokensByModel"] == {"qwen3-coder-plus": 2100, "qwen3.5-plus": 1350}, (record["todayTotalTokens"], record["todayTokensByModel"])
  assert record["todayPrompts"] == 4 and record["totalPrompts"] == 4, (record["todayPrompts"], record["totalPrompts"])
  assert record["totalSessions"] == 1 and record["todaySessions"] == 1, (record["totalSessions"], record["todaySessions"])
  assert record["activeDates"] == [date.today().isoformat()], record["activeDates"]
