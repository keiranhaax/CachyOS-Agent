#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Usage records: the Python collectors and their shared module, the update
# command, the text and JSON report, and the systemd timer.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

COLLECTORS=(claude codex grok kimi cursor grokbot copilot muse agy kimchi hermes devin vibe qwen
  opencode zai ollama minimax openrouter deepseek fireworks synthetic local)

# collect <agent> [args...]: a collector run the way the timer runs it, but in
# a clean environment: no API key, proxy or session bus of this machine
# reaches it, and a request that were made anyway goes to a closed local port.
# COLLECT_PATH is the PATH it sees: an empty directory unless a test needs rg.
collect() {
  local agent=$1
  shift
  env -i PATH="${COLLECT_PATH:-$SANDBOX/empty}" HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
    "$REPO_ROOT/bin/cachyos-agent-usage-$agent" "$@"
}

# is_json <json> <jq filter>: the filter is true for the document.
is_json() { jq -e "$2" >/dev/null <<<"$1"; }

# ---- the Python files -----------------------------------------------------------

begin "every Python file compiles"
make_sandbox
for file in "$REPO_ROOT"/lib/*.py "$REPO_ROOT"/bin/cachyos-agent-*; do
  [[ $file == *.py ]] || head -1 "$file" | grep -q python || continue
  PYTHONPYCACHEPREFIX=$SANDBOX/pyc python3 -m py_compile "$file" 2>&1 || fail "$file does not compile"
done
ok
cleanup_sandbox

begin "every collector is a hidden command with the standard metadata"
make_sandbox
for agent in "${COLLECTORS[@]}"; do
  file=$REPO_ROOT/bin/cachyos-agent-usage-$agent
  [[ -x $file ]] || fail "$agent has no executable collector"
  grep -q '^# cachyos-agent:hidden=true$' "$file" || fail "$agent is not hidden"
  grep -q '^# cachyos-agent:args=\[--force\] \[--limits-only\]$' "$file" || fail "$agent does not declare its flags"
  grep -q '^# SPDX-License-Identifier: GPL-3.0-only$' "$file" || fail "$agent has no SPDX line"
done
for file in "$REPO_ROOT"/lib/collectors.py "$REPO_ROOT"/bin/cachyos-agent-usage-*; do
  if grep -v '^# Adapted from Omarchy' "$file" | grep -qi omarchy; then fail "${file##*/} still names Omarchy"; fi
done
ok
cleanup_sandbox

# ---- collectors on a machine that does not use the agents -------------------------

begin "every collector prints the unused record on an empty machine"
make_sandbox
mkdir "$SANDBOX/empty"
for agent in "${COLLECTORS[@]}"; do
  record=$(collect "$agent" --force 2>"$SANDBOX/err") || fail "$agent exited nonzero: $(head -c 300 "$SANDBOX/err")"
  jq -e --arg id "$agent" '
    .schemaVersion == 1 and .id == $id and .ready == false and .limits == []
    and .usageStatusText == "" and (has("balance") | not) and .totalPrompts == 0
    and (.recentDays | length) == 7' <<<"$record" >/dev/null \
    || fail "$agent did not print the unused record: $(head -c 300 <<<"$record")"
done
ok
cleanup_sandbox

begin "a collector run through a symlink finds the shared module"
make_sandbox
mkdir "$SANDBOX/empty" "$SANDBOX/link"
ln -s "$REPO_ROOT/bin/cachyos-agent-usage-claude" "$SANDBOX/link/cachyos-agent-usage-claude"
record=$(env -i PATH="$SANDBOX/empty" HOME="$HOME" "$SANDBOX/link/cachyos-agent-usage-claude")
is_json "$record" '.id == "claude"' || fail "symlinked collector printed $record"
ok
cleanup_sandbox

# ---- the claude collector: local transcripts, no credentials ----------------------

begin "claude counts a local transcript and makes no request without credentials"
make_sandbox
mkdir "$SANDBOX/empty"
project=$HOME/.claude/projects/-home-keiran-demo
mkdir -p "$project"
now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
{
  printf '{"type":"user","uuid":"u1","sessionId":"s1","timestamp":"%s","message":{"role":"user","content":"hello"}}\n' "$now"
  printf '{"type":"assistant","uuid":"a1","sessionId":"s1","requestId":"r1","timestamp":"%s","message":{"id":"m1","role":"assistant","model":"claude-opus-4-1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}\n' "$now"
} >"$project/s1.jsonl"
record=$(collect claude --force 2>"$SANDBOX/err")
is_json "$record" '
  .ready == true and .hasLocalStats == true and .todayPrompts == 1 and .totalPrompts == 1
  and .totalSessions == 1 and .todayTotalTokens == 1350
  and .modelUsage["claude-opus-4-1"] == {inputTokens: 100, outputTokens: 50, cacheReadInputTokens: 1000, cacheCreationInputTokens: 200}' \
  || fail "local stats are wrong: $(head -c 600 <<<"$record")"
# Without a credential the collector returns before it builds a request, so
# the status is the no-credential one; a request to the closed proxy port would
# have turned it into "limits unavailable".
is_json "$record" '.usageStatusText == "Waiting for auth" and .limits == [] and .limitsStale == false' \
  || fail "expected the no-credential status: $(head -c 600 <<<"$record")"
[[ ! -s $SANDBOX/err ]] || fail "collector wrote to stderr: $(head -c 300 "$SANDBOX/err")"
ok
cleanup_sandbox

begin "claude reads the plan from a lapsed credential without asking the service"
make_sandbox
mkdir "$SANDBOX/empty"
mkdir -p "$HOME/.claude/projects"
past=$((($(date +%s) - 3600) * 1000))
future=$((($(date +%s) + 86400) * 1000))
printf '{"claudeAiOauth":{"accessToken":"fixture-not-a-token","expiresAt":%s,"refreshTokenExpiresAt":%s,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}\n' \
  "$past" "$future" >"$HOME/.claude/.credentials.json"
record=$(collect claude --force)
is_json "$record" '.tierLabel == "Max 5x" and .usageStatusText == "Limits paused" and .limits == []' \
  || fail "lapsed credential not reported: $(head -c 600 <<<"$record")"
[[ $record != *fixture-not-a-token* ]] || fail "the record leaks the access token"
ok
cleanup_sandbox

# ---- the hermes and local collectors: a state.db built by the test ----------------

# make_hermes_db: ~/.hermes/state.db with the tables the collector reads, holding
# a session on Nous Portal, one on a server on this machine and one on OpenAI.
make_hermes_db() {
  mkdir -p "$HOME/.hermes"
  python3 -I - "$HOME/.hermes/state.db" "$(date +%s)" <<'PY'
import sqlite3, sys
db, now = sys.argv[1], float(sys.argv[2])
conn = sqlite3.connect(db)
conn.executescript("""
CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, started_at REAL NOT NULL,
  model TEXT, billing_provider TEXT, billing_base_url TEXT);
CREATE TABLE session_model_usage (session_id TEXT NOT NULL, model TEXT NOT NULL,
  billing_provider TEXT NOT NULL DEFAULT '', billing_base_url TEXT NOT NULL DEFAULT '',
  input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens INTEGER NOT NULL DEFAULT 0, cache_write_tokens INTEGER NOT NULL DEFAULT 0);
CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
  role TEXT NOT NULL, timestamp REAL NOT NULL);
""")
sessions = [
  ("nous-1", "cli", "hermes-4", "nous", "https://inference-api.nousresearch.com/v1"),
  ("home-1", "cli", "llama3", "custom", "http://127.0.0.1:11434/v1"),
  ("openai-1", "cli", "gpt-5", "openai", "https://api.openai.com/v1"),
]
usage = {"nous-1": (1000, 200, 3000, 0), "home-1": (50, 10, 0, 0), "openai-1": (7, 7, 7, 7)}
prompts = {"nous-1": 2, "home-1": 1, "openai-1": 4}
for sid, source, model, provider, url in sessions:
  conn.execute("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?)", (sid, source, now, model, provider, url))
  conn.execute("INSERT INTO session_model_usage VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (sid, model, provider, url, *usage[sid]))
  for _ in range(prompts[sid]):
    conn.execute("INSERT INTO messages (session_id, role, timestamp) VALUES (?, 'user', ?)", (sid, now))
  conn.execute("INSERT INTO messages (session_id, role, timestamp) VALUES (?, 'assistant', ?)", (sid, now))
conn.commit()
PY
}

begin "hermes counts the sessions Nous Portal billed from a state.db"
make_sandbox
mkdir "$SANDBOX/empty"
make_hermes_db
record=$(collect hermes --force)
is_json "$record" '
  .ready == true and .hasLocalStats == true and .todayPrompts == 2 and .totalSessions == 1
  and .modelUsage == {"hermes-4": {inputTokens: 1000, outputTokens: 200, cacheReadInputTokens: 3000, cacheCreationInputTokens: 0}}' \
  || fail "hermes record is wrong: $(head -c 800 <<<"$record")"
ok
cleanup_sandbox

begin "local counts the session on this machine through the hermes reader"
make_sandbox
mkdir "$SANDBOX/empty"
make_hermes_db
record=$(collect local --force)
is_json "$record" '
  .ready == true and .todayPrompts == 1 and .totalSessions == 1
  and .modelUsage == {"llama3": {inputTokens: 50, outputTokens: 10, cacheReadInputTokens: 0, cacheCreationInputTokens: 0}}' \
  || fail "local record is wrong: $(head -c 800 <<<"$record")"
ok
cleanup_sandbox

begin "hermes reports an unreadable state.db instead of failing"
make_sandbox
mkdir "$SANDBOX/empty"
mkdir -p "$HOME/.hermes"
printf 'this is not a database, just a long enough text to look like one to sqlite\n' >"$HOME/.hermes/state.db"
record=$(collect hermes --force)
is_json "$record" '.ready == true and .usageStatusText == "Hermes unavailable"' \
  || fail "unreadable database not reported: $(head -c 600 <<<"$record")"
ok
cleanup_sandbox
