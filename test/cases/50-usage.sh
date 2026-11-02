#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Usage records: the Python collectors and their shared module, the update
# command, the text and JSON report, and the systemd timer.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
UPDATE=$REPO_ROOT/bin/cachyos-agent-usage-update
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

# calls <cmd>: the calls a stub recorded, one line per call.
calls() { awk -v RS= '{ gsub(/\n/, " "); print }' "$SANDBOX/calls/$1"; }

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

# ---- usage update ----------------------------------------------------------------

# make_root: $ROOT, a data root holding the update command and the dispatcher
# beside an empty set of collectors, so a test decides which collectors exist.
make_root() {
  ROOT=$SANDBOX/root
  mkdir -p "$ROOT/bin" "$ROOT/lib"
  cp "$REPO_ROOT/lib/common.sh" "$ROOT/lib/"
  cp "$REPO_ROOT/VERSION" "$ROOT/"
  cp "$UPDATE" "$AGENT" "$ROOT/bin/"
  USAGE=$XDG_STATE_HOME/cachyos-agent/usage
}

# add_collector <agent> <body>: bin/cachyos-agent-usage-<agent>. Its body runs
# after it has logged "<agent> <args>" to $SANDBOX/order.
add_collector() {
  printf '#!/bin/bash\necho "%s $*" >>"%s/order"\n%s\n' "$1" "$SANDBOX" "$2" >"$ROOT/bin/cachyos-agent-usage-$1"
  chmod +x "$ROOT/bin/cachyos-agent-usage-$1"
}

begin "update writes one record per collector and forwards the flags"
make_sandbox
make_root
for agent in alpha beta gamma; do
  add_collector "$agent" "echo '{\"id\":\"$agent\",\"ready\":true}'"
done
"$ROOT/bin/cachyos-agent-usage-update" --force --limits-only
for agent in alpha beta gamma; do
  [[ $(<"$USAGE/$agent.json") == "{\"id\":\"$agent\",\"ready\":true}" ]] || fail "$agent record is wrong or missing"
  grep -qx "$agent --force --limits-only" "$SANDBOX/order" || fail "$agent did not get the flags"
done
[[ $(find "$USAGE" -type f | wc -l) == 3 ]] || fail "temp files were left in the usage directory"
ok
cleanup_sandbox

begin "update does not run the commands that are not collectors"
make_sandbox
make_root
add_collector alpha "echo '{\"id\":\"alpha\"}'"
printf '#!/bin/bash\necho "ran schedule" >>"%s/order"\n' "$SANDBOX" >"$ROOT/bin/cachyos-agent-usage-schedule"
printf '#!/bin/bash\necho "ran report" >>"%s/order"\n' "$SANDBOX" >"$ROOT/bin/cachyos-agent-usage"
"$ROOT/bin/cachyos-agent-usage-update"
[[ $(<"$SANDBOX/order") == "alpha " ]] || fail "update ran something besides the collector: $(<"$SANDBOX/order")"
[[ $(ls "$USAGE") == alpha.json ]] || fail "update wrote records for non-collectors: $(ls "$USAGE")"
ok
cleanup_sandbox

begin "a failing collector is reported, the others are written, and its old record stays"
make_sandbox
make_root
mkdir -p "$USAGE"
printf '{"id":"bad","old":true}\n' >"$USAGE/bad.json"
printf '{"id":"junk","old":true}\n' >"$USAGE/junk.json"
printf '{"id":"scalar","old":true}\n' >"$USAGE/scalar.json"
add_collector good "echo '{\"id\":\"good\"}'"
add_collector bad "echo '{\"id\":\"bad\",\"old\":false}'; exit 3"
add_collector junk "echo 'not json'"
add_collector scalar "echo '[1,2]'"
if "$ROOT/bin/cachyos-agent-usage-update" 2>"$SANDBOX/err"; then fail "update succeeded although collectors failed"; fi
[[ $(<"$USAGE/good.json") == '{"id":"good"}' ]] || fail "the good collector's record was not written"
for agent in bad junk scalar; do
  [[ $(<"$USAGE/$agent.json") == "{\"id\":\"$agent\",\"old\":true}" ]] || fail "$agent's previous record was replaced"
  grep -q "$agent collector failed" "$SANDBOX/err" || fail "the $agent failure was not reported"
done
ok
cleanup_sandbox

begin "update honours --except and agent names"
make_sandbox
make_root
for agent in alpha beta gamma; do
  add_collector "$agent" "echo '{\"id\":\"$agent\"}'"
done
"$ROOT/bin/cachyos-agent-usage-update" --except beta --except gamma
[[ $(ls "$USAGE") == alpha.json ]] || fail "--except still wrote: $(ls "$USAGE")"
rm -rf "$USAGE" "$SANDBOX/order"
"$ROOT/bin/cachyos-agent-usage-update" gamma beta
[[ $(ls "$USAGE") == $'beta.json\ngamma.json' ]] || fail "agent names did not filter: $(ls "$USAGE")"
[[ $(sort "$SANDBOX/order") == $'beta \ngamma ' ]] || fail "unnamed collectors ran: $(<"$SANDBOX/order")"
rm -rf "$USAGE" "$SANDBOX/order"
if "$ROOT/bin/cachyos-agent-usage-update" nothere 2>"$SANDBOX/err"; then fail "an unknown agent was accepted"; fi
grep -q 'no collector for agent: nothere' "$SANDBOX/err" || fail "unknown agent not explained: $(<"$SANDBOX/err")"
[[ ! -e $SANDBOX/order ]] || fail "a collector ran despite the unknown agent"
if "$ROOT/bin/cachyos-agent-usage-update" --nonsense 2>/dev/null; then fail "an unknown option was accepted"; fi
ok
cleanup_sandbox

begin "update refreshes the account registry first and re-collects after a switch"
make_sandbox
make_root
for agent in claude codex; do
  add_collector "$agent" "echo '{\"id\":\"$agent\"}'"
done
stub cachyos-agent-account-state "$(
  cat <<EOF
echo "state \$*" >>"$SANDBOX/order"
[[ \$1 == autoswitch && \$2 == claude ]] && echo work || true
EOF
)"
mkdir -p "$XDG_STATE_HOME/cachyos-agent/accounts"
printf '{"accounts":[]}\n' >"$XDG_STATE_HOME/cachyos-agent/accounts/claude.json"
"$ROOT/bin/cachyos-agent-usage-update"
[[ $(head -1 "$SANDBOX/order") == "state refresh" ]] || fail "refresh did not run first: $(<"$SANDBOX/order")"
[[ $(tail -2 "$SANDBOX/order") == $'state autoswitch claude\nclaude --limits-only' ]] \
  || fail "no limits-only re-collect after the switch: $(<"$SANDBOX/order")"
[[ $(grep -c '^codex' "$SANDBOX/order") == 1 ]] || fail "codex has no registry and must be collected once"
ok
cleanup_sandbox

begin "update works without the account commands or an accounts directory"
make_sandbox
make_root
add_collector claude "echo '{\"id\":\"claude\"}'"
# An accounts registry but no account command: only the tools update itself needs.
mkdir "$SANDBOX/tools"
for tool in dirname readlink mkdir jq mktemp cat mv rm; do ln -s "$(command -v "$tool")" "$SANDBOX/tools/$tool"; done
mkdir -p "$XDG_STATE_HOME/cachyos-agent/accounts"
printf '{"accounts":[]}\n' >"$XDG_STATE_HOME/cachyos-agent/accounts/claude.json"
PATH=$SANDBOX/tools "$ROOT/bin/cachyos-agent-usage-update" || fail "update failed without cachyos-agent-account-state"
[[ -f $USAGE/claude.json ]] || fail "no record without the account command"
rm -rf "$XDG_STATE_HOME/cachyos-agent/accounts" "$USAGE"
stub cachyos-agent-account-state ''
"$ROOT/bin/cachyos-agent-usage-update"
[[ ! -e $SANDBOX/calls/cachyos-agent-account-state ]] || fail "account commands ran without an accounts directory"
ok
cleanup_sandbox

begin "update runs end to end through the dispatcher"
make_sandbox
make_root
add_collector alpha "echo '{\"id\":\"alpha\",\"ready\":true,\"name\":\"Alpha\"}'"
"$ROOT/bin/cachyos-agent" usage update alpha
[[ -f $USAGE/alpha.json ]] || fail "no record written through the dispatcher"
ok
cleanup_sandbox
