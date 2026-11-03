# SPDX-License-Identifier: GPL-3.0-only
# A machine running current Mistral Vibe on its Unified Harness store, on a
# Pro plan: a session today with a journal (and a subagent folded into it), one
# two days ago whose history is in chunks, one on a llama.cpp server on this
# machine, one on a model config.toml no longer names, and one not yet
# published. Vibe is read from local files alone, so no request goes out.

import hashlib
import json
import time
from datetime import date, datetime, timedelta

CONFIG = """\
active_model = "devstral-2"

[models.devstral-2]
name = "devstral-2512"
provider = "mistral"
alias = "devstral-2"

[models.codestral]
name = "codestral-2508"
provider = "mistral"
alias = "codestral"

[models.local-coder]
name = "qwen3-coder"
provider = "llamacpp"
alias = "local-coder"

[[providers]]
name = "mistral"
api_base = "https://api.mistral.ai/v1"
backend = "mistral"

[[providers]]
name = "llamacpp"
api_base = "http://127.0.0.1:8080/v1"
backend = "generic"
"""


def when(days_ago, hour=9):
  return (datetime.combine(date.today() - timedelta(days=days_ago), datetime.min.time()) + timedelta(hours=hour)).astimezone().isoformat()


def entry(entry_id, role, source=None):
  return {"id": entry_id, "type": "message", "role": role, **({"source": source} if source else {})}


def envelope(tokens, entries=()):
  inputs, cached, outputs = tokens
  usage = {"inputTokens": inputs, "cachedInputTokens": cached, "outputTokens": outputs}
  return {"session": {"createdAt": when(0), "tokenUsage": usage}, "history": {"entries": list(entries)}}


def store(root, session_id, snapshot, metadata=None, meta=None, journal=None, chunks=None):
  """One session as the Harness publishes it: CURRENT names generation g1, whose
  manifest names its documents, and the journal names what changed since."""
  directory = root / session_id
  generation = directory / "generations" / "g1"
  generation.mkdir(parents=True)
  (directory / "CURRENT").write_text(json.dumps({"generation": "g1"}))
  manifest = {"runtime_state": {"path": "runtime-state.json"}, "projection_state": {"path": "projection-state.json"}}
  if chunks:
    manifest["projection_state"]["chunks"] = [hashlib.sha256(json.dumps(chunk).encode()).hexdigest() for chunk in chunks]
    (directory / "chunks").mkdir()
    for digest, chunk in zip(manifest["projection_state"]["chunks"], chunks):
      (directory / "chunks" / f"{digest}.json").write_text(json.dumps(chunk))
  if journal is not None:
    manifest["recovery_journal_segment"] = {"path": "journal/0000000000000001.jsonl"}
    (directory / "journal").mkdir()
    (directory / "journal" / "0000000000000001.jsonl").write_text(journal)
  (generation / "manifest.json").write_text(json.dumps(manifest))
  (generation / "runtime-state.json").write_text(json.dumps({"session_metadata": metadata or {}}))
  (generation / "projection-state.json").write_text(json.dumps({"snapshot": snapshot}))
  if meta is not None:
    (directory / "meta.json").write_text(json.dumps(meta))


def setup(home, bin):
  vibe = home / ".vibe"
  root = vibe / "logs" / "session" / "unified"
  vibe.mkdir()
  (vibe / "config.toml").write_text(CONFIG)
  # The newest answer names the plan; an older one from before an upgrade does not.
  now = time.time()
  (vibe / "whoami_cache.json").write_text(json.dumps({
    "key-old": {"stored_at_timestamp": now - 3 * 86400, "payload": {"plan_type": "chat", "plan_name": "FREE"}},
    "key-new": {"stored_at_timestamp": now - 60, "payload": {"plan_type": "chat", "plan_name": "INDIVIDUAL"}},
  }))

  # Typed turns are turn_start and turn_steer; a reminder is Vibe's own.
  journal = [
    {"type": "projection_delta", "payload": {"delta": [
      {"op": "append_entry", "entry": entry("e5", "user", "turn_start")},
      {"op": "remove_entry", "id": "e4"},
      {"op": "replace_entry", "id": "e3", "entry": entry("e3", "user", "turn_steer")},
      {"op": "set_envelope", "state": envelope((14000, 5000, 2100))},
    ]}},
  ]
  # The last record is still being appended: it has no newline yet.
  unfinished = {"type": "projection_delta", "payload": {"delta": [{"op": "append_entry", "entry": entry("e6", "user", "turn_start")}]}}
  store(
    root, "s-main", envelope((10000, 4000, 1500), [
      entry("e1", "user", "turn_start"), entry("e2", "assistant"), entry("e3", "user", "reminder"), entry("e4", "user", "turn_steer"),
    ]),
    meta={"start_time": when(0), "config": {"active_model": "devstral-2"}},
    journal="".join(json.dumps(record) + "\n" for record in journal) + json.dumps(unfinished),
  )
  # A subagent is a session of the store but counts toward the one that spawned it.
  store(
    root, "s-sub", envelope((3000, 1000, 400), [entry("f1", "user", "turn_start")]),
    metadata={"subagent_spawn_key": "spawn-1", "root_session_id": "s-main", "active_model": "devstral-2"},
  )
  store(
    root, "s-chunked", envelope((5000, 0, 700)),
    meta={"start_time": when(2), "config": {"active_model": "codestral"}},
    chunks=[
      [entry("c1", "user", "turn_start"), entry("c2", "assistant")],
      [entry("c3", "user", "turn_start"), entry("c4", "user", "turn_steer")],
    ],
  )
  store(
    root, "s-local", envelope((50000, 0, 9000), [entry("l1", "user", "turn_start")]),
    meta={"start_time": when(0), "config": {"active_model": "local-coder"}},
  )
  store(
    root, "s-ghost", envelope((60000, 0, 9000), [entry("g1", "user", "turn_start")]),
    meta={"start_time": when(0), "config": {"active_model": "retired-model"}},
  )
  # Vibe has not published this session yet: no CURRENT.
  (root / "s-pending").mkdir()
  (root / "s-pending" / "meta.json").write_text(json.dumps({"start_time": when(0), "config": {"active_model": "devstral-2"}}))


def check(record, requests):
  assert requests == [], requests
  assert record["ready"] is True and record["hasLocalStats"] is True, (record["ready"], record["hasLocalStats"])
  assert record["tierLabel"] == "Pro", record["tierLabel"]
  # Mistral publishes no limits: no meters, and nothing waiting on a sign-in.
  assert record["limits"] == [] and record["usageStatusText"] == "" and record["authHelpText"] == "", (record["limits"], record["usageStatusText"], record["authHelpText"])

  today, two_days_ago = date.today(), date.today() - timedelta(days=2)
  # s-main after its journal: e1, e3 (now a steer), e5; the subagent's turn is no prompt.
  assert record["totalPrompts"] == 6 and record["todayPrompts"] == 3, (record["totalPrompts"], record["todayPrompts"])
  assert record["totalSessions"] == 2 and record["todaySessions"] == 1, (record["totalSessions"], record["todaySessions"])
  assert record["modelUsage"] == {
    "devstral-2": {"inputTokens": 11000, "outputTokens": 2500, "cacheReadInputTokens": 6000, "cacheCreationInputTokens": 0},
    "codestral": {"inputTokens": 5000, "outputTokens": 700, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0},
  }, record["modelUsage"]
  assert record["todayTotalTokens"] == 19500 and record["todayTokensByModel"] == {"devstral-2": 19500}, (record["todayTotalTokens"], record["todayTokensByModel"])
  tokens = {day["date"]: day["messageCount"] for day in record["recentDays"]}
  assert tokens[today.isoformat()] == 19500 and tokens[two_days_ago.isoformat()] == 5700 and sum(tokens.values()) == 25200, tokens
  assert record["activeDays"] == 2 and record["activeDates"] == [two_days_ago.isoformat(), today.isoformat()], (record["activeDays"], record["activeDates"])
