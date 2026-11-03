#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Usage records: the Python collectors and their shared module, the update
# command, the text and JSON report, and the systemd timer.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
UPDATE=$REPO_ROOT/bin/cachyos-agent-usage-update
REPORT=$REPO_ROOT/bin/cachyos-agent-usage
SCHEDULE=$REPO_ROOT/bin/cachyos-agent-usage-schedule
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

begin "no collector imports a name it never uses or cites the panel's refreshLimits() call"
make_sandbox
unused=$(python3 -I - "$REPO_ROOT"/bin/cachyos-agent-usage-* <<'PY'
import ast, sys
for path in sys.argv[1:]:
  source = open(path).read()
  if not source.startswith("#!/usr/bin/python"):
    continue
  tree = ast.parse(source)
  used = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
  for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom) and node.module != "__future__":
      for alias in node.names:
        if (alias.asname or alias.name) not in used:
          print(f"{path.rsplit('/', 1)[-1]}: {alias.name}")
PY
)
[[ -z $unused ]] || fail "imported and never used: $unused"
if grep -n 'refreshLimits' "$REPO_ROOT"/lib/collectors.py "$REPO_ROOT"/bin/cachyos-agent-usage-*; then
  fail "a comment still cites the removed panel's refreshLimits() call"
fi
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

begin "a collector run through a symlink finds the shared module and its sibling collectors"
make_sandbox
mkdir "$SANDBOX/empty" "$SANDBOX/link"
# local reads the other harness collectors beside itself, so a link in a
# directory that holds only the link must still reach the real ones.
for agent in claude local; do
  ln -s "$REPO_ROOT/bin/cachyos-agent-usage-$agent" "$SANDBOX/link/cachyos-agent-usage-$agent"
  record=$(env -i PATH="$SANDBOX/empty" HOME="$HOME" "$SANDBOX/link/cachyos-agent-usage-$agent" 2>"$SANDBOX/err") \
    || fail "symlinked $agent exited nonzero: $(tail -n 3 "$SANDBOX/err")"
  is_json "$record" ".id == \"$agent\"" || fail "symlinked $agent printed $record"
done
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
  cp "$UPDATE" "$REPORT" "$SCHEDULE" "$AGENT" "$ROOT/bin/"
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
# One argument holding two known names is a typo, not a request for either.
for args in "alpha beta" "alp"; do
  if "$ROOT/bin/cachyos-agent-usage-update" "$args" 2>"$SANDBOX/err"; then fail "'$args' was accepted as an agent name"; fi
  grep -q 'no collector for agent' "$SANDBOX/err" || fail "'$args' not explained: $(<"$SANDBOX/err")"
  if "$ROOT/bin/cachyos-agent-usage-update" --except "$args" 2>"$SANDBOX/err"; then fail "--except '$args' was accepted"; fi
  grep -q 'no collector for agent' "$SANDBOX/err" || fail "--except '$args' not explained: $(<"$SANDBOX/err")"
done
[[ ! -e $SANDBOX/order && ! -e $USAGE ]] || fail "a collector ran or a record was written for a name that matched none"
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
[[ $("$ROOT/bin/cachyos-agent" usage --json | jq -r '.[0].name') == Alpha ]] || fail "usage --json does not read what update wrote"
ok
cleanup_sandbox

# ---- the report ------------------------------------------------------------------

# write_record <agent> <jq args...> <jq program>: a record file in the sandbox.
write_record() {
  local agent=$1
  shift
  mkdir -p "$XDG_STATE_HOME/cachyos-agent/usage"
  jq -n "$@" >"$XDG_STATE_HOME/cachyos-agent/usage/$agent.json"
}

iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# Times lie 30 seconds beyond a minute boundary, so the seconds a test takes
# do not change the minutes the report prints.
# shellcheck disable=SC2016 # the $names in the programs are jq variables
make_report_fixtures() {
  local now
  now=$(date +%s)
  write_record claude --arg updated "$(iso "$now")" \
    --arg session "$(iso $((now + 2 * 3600 + 13 * 60 + 30)))" \
    --arg weekly "$(iso $((now + 4 * 86400 + 3 * 3600 + 5 * 60 + 30)))" '
    {schemaVersion: 1, id: "claude", name: "Claude Code", ready: true, updatedAt: $updated,
     tierLabel: "max 5x", usageStatusText: "", authHelpText: "",
     limits: [{label: "Session (5-hour)", percent: 0.42, resetsAt: $session},
              {label: "Weekly (7-day)", percent: 0.17, resetsAt: $weekly}],
     limitsStale: false, limitsFetchedAt: 0, hasLocalStats: true, hasPromptStats: true,
     todayPrompts: 12, totalPrompts: 340, todayTotalTokens: 1234567,
     recentDays: ([range(0; 6) | {date: "d\(.)", messageCount: 200000}] + [{date: "d6", messageCount: 1234567}])}'
  write_record codex --arg updated "$(iso $((now - 3 * 3600 - 30)))" \
    --arg elapsed "$(iso $((now - 3600)))" --arg session "$(iso $((now + 20 * 60 + 30)))" \
    --arg tomorrow "$(iso $((now + 86400 + 30)))" \
    --argjson fetched "$(((now - 25 * 60 - 30) * 1000))" --argjson work_fetched "$(((now - 5 * 60 - 30) * 1000))" '
    {schemaVersion: 1, id: "codex", name: "Codex", ready: true, updatedAt: $updated, tierLabel: "",
     usageStatusText: "Sign-in expired", authHelpText: "Run `codex login` to authenticate.",
     limits: [{label: "Weekly", percent: 0.9, resetsAt: $elapsed},
              {label: "Session", percent: 0.5, resetsAt: $session},
              {label: "Monthly", percent: 1, resetsAt: ""}],
     limitsStale: true, limitsFetchedAt: $fetched,
     accounts: [
       {id: "work", label: "work", plan: "Pro", active: true, stale: true, fetchedAt: $work_fetched,
        usageStatusText: "", authHelpText: "Limits paused",
        limits: [{label: "Weekly", percent: 0.3, resetsAt: $tomorrow}]},
       {id: "home", label: "home", plan: "Plus", active: false, limits: []}]}'
  write_record deepseek '
    {schemaVersion: 1, id: "deepseek", name: "DeepSeek", ready: true, tierLabel: "Prepaid", limits: [],
     balance: {remaining: 3, funded: 0, spent: 0, currency: "CNY", estimated: true}}'
  write_record kimi '{schemaVersion: 1, id: "kimi", name: "Kimi", ready: false, limits: []}'
  write_record openrouter '
    {schemaVersion: 1, id: "openrouter", name: "OpenRouter", ready: true, tierLabel: "Prepaid", limits: [],
     balance: {remaining: 12.34, funded: 20, spent: 7.66, currency: "USD", estimated: false}}'
}

begin "the report shows limits, balances, tokens, prompts and stale records"
make_sandbox
make_report_fixtures
expected=$(
  cat <<'EOF'
Claude Code  Max 5x
  Session (5-hour)  42%  resets in 2h 13m
  Weekly (7-day)    17%  resets in 4d 3h
  Tokens            today 1.2M, this week 2.4M
  Prompts           today 12, all time 340

Codex  (updated 3h 0m ago)
  Weekly   0%
  Session  50%  resets in 20m
  Monthly  100%
  limits are stale (last checked 25m ago)
  ! Sign-in expired: Run `codex login` to authenticate.
  Accounts
    work  Pro  (active)
      Weekly  30%  resets in 1d 0h
      limits are stale (last checked 5m ago)
      ! Limits paused
    home  Plus

DeepSeek  Prepaid
  Balance  about CNY 3.00 left

OpenRouter  Prepaid
  Balance  $12.34 left of $20.00 (spent $7.66)
EOF
)
actual=$("$REPORT")
[[ $actual == "$expected" ]] || { diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true; fail "the report differs from the expected text"; }
[[ $("$AGENT" usage) == "$expected" ]] || fail "the report differs through the dispatcher"
ok
cleanup_sandbox

begin "the report filters by agent name and says when one is not in use"
make_sandbox
make_report_fixtures
out=$("$REPORT" kimi openrouter)
[[ $out == $'Kimi: not in use on this machine\n\nOpenRouter  Prepaid\n  Balance  $12.34 left of $20.00 (spent $7.66)' ]] || fail "filtered report is wrong: $out"
[[ $("$AGENT" usage -- openrouter) == *"OpenRouter  Prepaid"* && $("$AGENT" usage -- openrouter) != *Codex* ]] \
  || fail "usage -- <agent> did not filter through the dispatcher"
if "$REPORT" ghost 2>"$SANDBOX/err"; then fail "an agent without a record succeeded"; fi
grep -q 'no usage record for: ghost' "$SANDBOX/err" || fail "missing record not explained: $(<"$SANDBOX/err")"
if "$REPORT" --bogus 2>/dev/null; then fail "an unknown option was accepted"; fi
if "$REPORT" '../x' 2>/dev/null; then fail "a path was accepted as an agent name"; fi
ok
cleanup_sandbox

begin "usage --json prints the raw records as an array in file order"
make_sandbox
make_report_fixtures
printf '{broken' >"$XDG_STATE_HOME/cachyos-agent/usage/aaa.json"
json=$("$AGENT" usage --json 2>"$SANDBOX/err")
is_json "$json" 'type == "array" and map(.id) == ["claude","codex","deepseek","kimi","openrouter"]' || fail "wrong ids or order: $(head -c 300 <<<"$json")"
is_json "$json" '.[0].limits[0].percent == 0.42 and .[3].ready == false' || fail "records are not the raw ones"
grep -q 'aaa.json' "$SANDBOX/err" || fail "the broken record was not reported"
[[ $("$REPORT" --json openrouter kimi | jq -c 'map(.id)') == '["kimi","openrouter"]' ]] || fail "--json with names does not filter in file order"
ok
cleanup_sandbox

begin "the report with no records says how to make some"
make_sandbox
out=$("$REPORT")
[[ $out == *"cachyos-agent usage update"* ]] || fail "no hint: $out"
[[ $("$REPORT" --json) == '[]' ]] || fail "--json without records is not an empty array"
[[ $("$REPORT" --help) == "Usage: cachyos-agent usage [--json] [--] [agent...]"* ]] || fail "no help text"
ok
cleanup_sandbox

begin "the group help shows how to filter the report without running a collector"
make_sandbox
# The dispatcher takes the longest matching command, so a first word that names
# an agent runs that agent's collector instead of filtering the report. The
# help the dispatcher prints is all most people see: it must not suggest it.
help=$("$AGENT" usage --help)
[[ $help == *"cachyos-agent usage -- claude codex"* ]] || fail "no filtering example in the group help"
[[ $help == *"a bare name runs that agent's collector"* ]] || fail "the group help does not warn about bare agent names"
bad=$("$AGENT" commands --json | jq -r '.commands[] | select(.route == "cachyos-agent usage") | .examples[] | select(test("^cachyos-agent usage [a-z]"))')
[[ -z $bad ]] || fail "an example puts an agent name first: $bad"
ok
cleanup_sandbox

begin "the report says so when records exist but no agent is in use"
make_sandbox
write_record kimi '{schemaVersion: 1, id: "kimi", name: "Kimi", ready: false, limits: []}'
write_record zai '{schemaVersion: 1, id: "zai", name: "Z.ai", ready: false, limits: []}'
out=$("$REPORT")
[[ $out == "No agent is in use on this machine"* ]] || fail "expected the not-in-use message, got: $(printf '%q' "$out")"
[[ $("$REPORT" --json | jq length) == 2 ]] || fail "--json lost the unused records"
[[ $("$REPORT" kimi) == "Kimi: not in use on this machine" ]] || fail "a named unused agent is no longer reported by name"
ok
cleanup_sandbox

begin "the file order is byte order whatever LC_ALL says"
make_sandbox
# Most locales ignore punctuation when collating, which puts grokbot.json
# before grok.json; byte order puts the dot first.
for agent in hermes grokbot grok claude; do
  # shellcheck disable=SC2016 # $id is a jq variable
  write_record "$agent" --arg id "$agent" '{schemaVersion: 1, id: $id, name: $id, ready: true, limits: []}'
done
for locale in C en_US.utf8 C.utf8; do
  got=$(LC_ALL=$locale "$REPORT" --json | jq -c 'map(.id)')
  [[ $got == '["claude","grok","grokbot","hermes"]' ]] || fail "LC_ALL=$locale gave $got"
  got=$(LC_ALL=$locale "$REPORT" | grep -v '^$' | tr '\n' ' ')
  [[ $got == 'claude grok grokbot hermes ' ]] || fail "LC_ALL=$locale text report order: $got"
done
ok
cleanup_sandbox

begin "the report prints no control characters from a record"
make_sandbox
# A label, a status or a name can come from a vendor's response: an escape
# sequence in one must not reach the terminal, nor a newline start a line of
# its own. The C1 control U+009B is a one-character escape on some terminals.
# shellcheck disable=SC2016 # the $names in the program are jq variables
write_record evil --arg esc $'\033' --arg bel $'\a' --arg nl $'\n' --arg c1 $'\xc2\x9b' '
  {schemaVersion: 1, id: "evil", name: ("Ev" + $esc + "[2Jil"), ready: true, tierLabel: ("pro" + $nl + "FAKE"),
   usageStatusText: ($esc + "]0;owned" + $bel), authHelpText: ("help" + $c1 + "31m"),
   limits: [{label: ($esc + "]0;title" + $bel + "Window" + $esc + "[2J"), percent: 0.5, resetsAt: ""}],
   balance: {remaining: 1, funded: 2, spent: 1, currency: ("X" + $esc + "[1mY")},
   accounts: [{label: ("acct" + $esc + "[0m"), plan: ("plan" + $bel), active: true, limits: []}]}'
expected=$(
  cat <<'EOF'
Ev[2Jil  ProFAKE
  ]0;titleWindow[2J  50%
  Balance            X[1MY 1.00 left of X[1MY 2.00 (spent X[1MY 1.00)
  ! ]0;owned: help31m
  Accounts
    acct[0m  plan  (active)
EOF
)
out=$("$REPORT")
[[ $out == "$expected" ]] || { diff <(printf '%s\n' "$expected") <(printf '%s\n' "$out") | cat -v >&2 || true; fail "the report did not strip the control characters"; }
ok
cleanup_sandbox

begin "the report copes with a record of the wrong shapes"
make_sandbox
mkdir -p "$XDG_STATE_HOME/cachyos-agent/usage"
printf '%s\n' '{"id":"odd","name":"Odd","ready":true,"limits":"nope","recentDays":5,"accounts":"x","balance":7,"todayTotalTokens":"many","updatedAt":12,"tierLabel":3}' \
  >"$XDG_STATE_HOME/cachyos-agent/usage/odd.json"
[[ $("$REPORT") == Odd ]] || fail "a malformed record changed the report: $("$REPORT")"
ok
cleanup_sandbox

begin "the report reads a reset time in every form the collectors let through"
make_sandbox
now=$(date +%s)
reset=$((now + 2 * 3600 + 13 * 60 + 30))
# The same instant five ways: basic form, a space separator with a comma
# fraction, +HH and +HHMM offsets, and a time with no offset, which is UTC.
# The last one has no seconds, so it is written 30 s later to land on the
# same minute boundary as the others.
# shellcheck disable=SC2016 # the $names are jq variables
write_record claude --arg basic "$(date -u -d "@$reset" +%Y%m%dT%H%M%SZ)" \
  --arg spaced "$(date -u -d "@$reset" '+%Y-%m-%d %H:%M:%S,5Z')" \
  --arg hours "$(TZ=Etc/GMT-2 date -d "@$reset" +%Y-%m-%dT%H:%M:%S+02)" \
  --arg compact "$(TZ=Etc/GMT+5 date -d "@$reset" +%Y-%m-%dT%H:%M:%S-0500)" \
  --arg naked "$(date -u -d "@$((reset + 30))" +%Y-%m-%dT%H:%M)" '
  {schemaVersion: 1, id: "claude", name: "Claude Code", ready: true,
   limits: [{label: "Basic", percent: 0.1, resetsAt: $basic},
            {label: "Spaced", percent: 0.2, resetsAt: $spaced},
            {label: "Hours", percent: 0.3, resetsAt: $hours},
            {label: "Compact", percent: 0.4, resetsAt: $compact},
            {label: "Naked", percent: 0.5, resetsAt: $naked},
            {label: "Garbled", percent: 0.6, resetsAt: "tomorrow"}]}'
out=$("$AGENT" usage)
for label in Basic Spaced Hours Compact Naked; do
  row=$(grep -F "  $label " <<<"$out") || fail "no row for $label: $out"
  [[ $row == *"  resets in 2h 13m" ]] || fail "$label is not read as the same instant: [$row]"
done
row=$(grep -F "  Garbled " <<<"$out") || fail "no row for Garbled: $out"
[[ $row == *"Garbled  60%" ]] || fail "a garbled time should print its row with no reset: [$row]"
ok
cleanup_sandbox

# ---- the timer -------------------------------------------------------------------

begin "the shipped units run the update on a 15 minute timer"
make_sandbox
service=$REPO_ROOT/systemd/user/cachyos-agent-usage-update.service
timer=$REPO_ROOT/systemd/user/cachyos-agent-usage-update.timer
for line in 'Type=oneshot' 'ExecStart=/usr/bin/cachyos-agent-usage-update'; do
  grep -qx "$line" "$service" || fail "service lacks $line"
done
for line in 'OnBootSec=2min' 'OnUnitActiveSec=15min' 'Persistent=true' 'WantedBy=timers.target'; do
  grep -qx "$line" "$timer" || fail "timer lacks $line"
done
ok
cleanup_sandbox

begin "schedule on from a checkout writes units that point at it, then enables the timer"
make_sandbox
stub systemctl
units=$XDG_CONFIG_HOME/systemd/user
"$SCHEDULE" on >/dev/null
[[ $(calls systemctl) == $'--user daemon-reload\n--user enable --now cachyos-agent-usage-update.timer' ]] \
  || fail "unexpected systemctl calls: $(calls systemctl)"
grep -qx "ExecStart=\"$REPO_ROOT/bin/cachyos-agent-usage-update\"" "$units/cachyos-agent-usage-update.service" \
  || fail "the service does not run the checkout's update: $(<"$units/cachyos-agent-usage-update.service")"
! grep -q '/usr/bin' "$units/cachyos-agent-usage-update.service" || fail "the packaged path is still in the service"
diff <(tail -n +2 "$units/cachyos-agent-usage-update.timer") "$REPO_ROOT/systemd/user/cachyos-agent-usage-update.timer" \
  || fail "the timer differs from the shipped one"
head -1 "$units/cachyos-agent-usage-update.timer" | grep -q '^# Generated by cachyos-agent usage schedule' || fail "generated units are not marked"
rm "$SANDBOX/calls/systemctl"
"$SCHEDULE" on >/dev/null
[[ $(grep -c enable "$SANDBOX/calls/systemctl") == 1 ]] || fail "a second on did not enable again"
ok
cleanup_sandbox

begin "schedule off disables the timer and removes only the units it wrote"
make_sandbox
stub systemctl
units=$XDG_CONFIG_HOME/systemd/user
"$SCHEDULE" on >/dev/null
rm "$SANDBOX/calls/systemctl"
"$SCHEDULE" off
[[ $(calls systemctl) == $'--user cat cachyos-agent-usage-update.timer\n--user disable --now cachyos-agent-usage-update.timer\n--user daemon-reload' ]] \
  || fail "unexpected systemctl calls: $(calls systemctl)"
[[ ! -e $units/cachyos-agent-usage-update.service && ! -e $units/cachyos-agent-usage-update.timer ]] || fail "generated units remain"
printf '[Timer]\nOnBootSec=1h\n' >"$units/cachyos-agent-usage-update.timer"
"$SCHEDULE" off
[[ -f $units/cachyos-agent-usage-update.timer ]] || fail "off removed a unit the user wrote"
ok
cleanup_sandbox

begin "schedule on refuses to overwrite a unit it did not write"
make_sandbox
stub systemctl
units=$XDG_CONFIG_HOME/systemd/user
mkdir -p "$units"
printf '[Timer]\nOnBootSec=1h\n' >"$units/cachyos-agent-usage-update.timer"
if "$SCHEDULE" on 2>"$SANDBOX/err"; then fail "on succeeded over a foreign unit"; fi
grep -q 'was not written by this command' "$SANDBOX/err" || fail "the refusal is not explained"
[[ $(<"$units/cachyos-agent-usage-update.timer") == $'[Timer]\nOnBootSec=1h' ]] || fail "the foreign unit was changed"
[[ ! -e $SANDBOX/calls/systemctl ]] || fail "systemctl ran despite the refusal"
ok
cleanup_sandbox

begin "schedule on from the package enables the installed timer and writes nothing"
make_sandbox
stub systemctl
make_root
"$ROOT/bin/cachyos-agent-usage-schedule" on >/dev/null
[[ $(calls systemctl) == '--user enable --now cachyos-agent-usage-update.timer' ]] \
  || fail "unexpected systemctl calls: $(calls systemctl)"
[[ ! -e $XDG_CONFIG_HOME/systemd ]] || fail "the packaged mode wrote unit files"
ok
cleanup_sandbox

# make_checkout <dir>: a copy of the data root laid out like a Git checkout,
# with the shipped units, for a test that needs an odd path.
make_checkout() {
  mkdir -p "$1/systemd"
  cp -r "$ROOT/bin" "$ROOT/lib" "$ROOT/VERSION" "$1/"
  cp -r "$REPO_ROOT/systemd/user" "$1/systemd/"
}

# fake_systemd: a systemctl that knows the timer only while a unit file sits in
# the user's config directory or $XDG_RUNTIME_DIR/packaged exists, and fails on
# cat and disable for a unit it does not know, as the real one does.
fake_systemd() {
  stub systemctl "$(
    cat <<'EOF'
case "$*" in
  *" cat "* | *" disable "*)
    if [[ ! -e $XDG_CONFIG_HOME/systemd/user/cachyos-agent-usage-update.timer && ! -e $XDG_RUNTIME_DIR/packaged ]]; then
      echo "Failed: Unit cachyos-agent-usage-update.timer does not exist" >&2
      exit 1
    fi
    ;;
esac
EOF
  )"
}

begin "schedule quotes a checkout path that systemd would otherwise split or expand"
make_sandbox
stub systemctl
make_root
# A space splits the word, % starts a specifier and is doubled. A $ stays as it
# is: systemd expands variables in the arguments, never in the executable.
odd="$SANDBOX/my checkout 50%/a\$b"
make_checkout "$odd"
"$odd/bin/cachyos-agent-usage-schedule" on >/dev/null
units=$XDG_CONFIG_HOME/systemd/user
grep -qxF "ExecStart=\"$SANDBOX/my checkout 50%%/a\$b/bin/cachyos-agent-usage-update\"" \
  "$units/cachyos-agent-usage-update.service" || fail "the path was not escaped: $(<"$units/cachyos-agent-usage-update.service")"
if command -v systemd-analyze >/dev/null; then
  # What systemd reads is what counts: a line that looks right can name a path that does not exist.
  problems=$(systemd-analyze --user verify "$units/cachyos-agent-usage-update.service" "$units/cachyos-agent-usage-update.timer" 2>&1 \
    | grep cachyos-agent-usage-update || true)
  [[ -z $problems ]] || fail "systemd rejects the generated unit: $problems"
fi
ok
cleanup_sandbox

begin "schedule on refuses a checkout path that systemd cannot run and writes nothing"
make_sandbox
stub systemctl
make_root
# systemd refuses these in the executable of ExecStart= however they are escaped.
for name in 'q"uote' "q'uote" 'back\slash' $'tab\tname'; do
  make_checkout "$SANDBOX/$name"
  if "$SANDBOX/$name/bin/cachyos-agent-usage-schedule" on 2>"$SANDBOX/err"; then fail "on succeeded from $(printf '%q' "$name")"; fi
  grep -q 'systemd refuses' "$SANDBOX/err" || fail "refusal for $(printf '%q' "$name") not explained: $(<"$SANDBOX/err")"
  [[ ! -e $XDG_CONFIG_HOME/systemd ]] || fail "units were written for $(printf '%q' "$name")"
  [[ ! -e $SANDBOX/calls/systemctl ]] || fail "systemctl ran for $(printf '%q' "$name")"
  rm -rf -- "${SANDBOX:?}/$name"
done
ok
cleanup_sandbox

begin "schedule off can be repeated and works when the timer was never turned on"
make_sandbox
fake_systemd
"$SCHEDULE" off || fail "off failed on a machine that never ran on"
[[ $(calls systemctl) == '--user cat cachyos-agent-usage-update.timer' ]] || fail "off touched an unknown timer: $(calls systemctl)"
"$SCHEDULE" on >/dev/null
"$SCHEDULE" off || fail "off failed after on"
rm "$SANDBOX/calls/systemctl"
"$SCHEDULE" off || fail "a second off failed"
[[ $(calls systemctl) == '--user cat cachyos-agent-usage-update.timer' ]] || fail "a second off disabled again: $(calls systemctl)"
[[ ! -e $XDG_CONFIG_HOME/systemd/user/cachyos-agent-usage-update.service ]] || fail "generated units remain"
# An installed timer is disabled, and nothing is removed.
touch "$XDG_RUNTIME_DIR/packaged"
rm "$SANDBOX/calls/systemctl"
"$SCHEDULE" off
[[ $(calls systemctl) == $'--user cat cachyos-agent-usage-update.timer\n--user disable --now cachyos-agent-usage-update.timer' ]] \
  || fail "off did not disable the installed timer: $(calls systemctl)"
ok
cleanup_sandbox

begin "schedule on from the package retires the units it wrote for a checkout"
make_sandbox
fake_systemd
units=$XDG_CONFIG_HOME/systemd/user
"$SCHEDULE" on >/dev/null
# The package is installed and the checkout is gone: only the installed units
# remain, and a copy in ~/.config would shadow them and run the vanished checkout.
make_root
touch "$XDG_RUNTIME_DIR/packaged"
rm "$SANDBOX/calls/systemctl"
"$ROOT/bin/cachyos-agent-usage-schedule" on >/dev/null
[[ $(calls systemctl) == $'--user cat cachyos-agent-usage-update.timer\n--user disable --now cachyos-agent-usage-update.timer\n--user daemon-reload\n--user enable --now cachyos-agent-usage-update.timer' ]] \
  || fail "unexpected systemctl calls: $(calls systemctl)"
[[ ! -e $units/cachyos-agent-usage-update.service && ! -e $units/cachyos-agent-usage-update.timer ]] || fail "generated units remain"
# A unit the user wrote is theirs: it stays, and is not disabled behind their back.
printf '[Timer]\nOnBootSec=1h\n' >"$units/cachyos-agent-usage-update.timer"
rm "$SANDBOX/calls/systemctl"
"$ROOT/bin/cachyos-agent-usage-schedule" on >/dev/null
[[ $(calls systemctl) == '--user enable --now cachyos-agent-usage-update.timer' ]] || fail "on touched a foreign unit: $(calls systemctl)"
[[ -f $units/cachyos-agent-usage-update.timer ]] || fail "the foreign unit was removed"
ok
cleanup_sandbox

begin "the timer's environment is documented, and a config file reaches a collector without it"
make_sandbox
stub systemctl
mkdir "$SANDBOX/empty"
# The timer runs under the systemd user manager, which never saw what the
# user's shell exports. The collectors keep working there when the key is in a
# file, so say where to put it, in the places a person looks.
out=$("$SCHEDULE" on)
for text in "$out" "$("$SCHEDULE" --help)" "$(<"$REPO_ROOT/systemd/user/cachyos-agent-usage-update.service")"; do
  [[ $text == *environment.d* && $text == *config.fish* ]] || fail "no note on the timer's environment in: $text"
done
[[ $("$AGENT" usage update --help) == *environment.d* ]] || fail "usage update --help does not mention the timer's environment"
record=$(collect zai --force)
is_json "$record" '.ready == false' || fail "zai is in use without any key: $(head -c 300 <<<"$record")"
mkdir -p "$XDG_CONFIG_HOME/cachyos-agent"
printf '{"apiKey":"key-from-the-file"}\n' >"$XDG_CONFIG_HOME/cachyos-agent/zai.json"
record=$(collect zai --force)
is_json "$record" '.ready == true' || fail "a key in the config file did not reach the collector: $(head -c 300 <<<"$record")"
[[ $record != *key-from-the-file* ]] || fail "the record leaks the key"
ok
cleanup_sandbox

begin "schedule status reports the timer's state and works through the dispatcher"
make_sandbox
stub systemctl 'case "$*" in *is-enabled*) echo enabled ;; *is-active*) echo active ;; esac'
[[ $("$AGENT" usage schedule status) == "enabled, active" ]] || fail "status: $("$AGENT" usage schedule status)"
[[ $("$SCHEDULE") == "enabled, active" ]] || fail "status is not the default action"
stub systemctl 'case "$*" in *is-enabled*) echo disabled; exit 1 ;; *is-active*) echo inactive; exit 3 ;; esac'
[[ $("$SCHEDULE" status) == "disabled, inactive" ]] || fail "status of a stopped timer: $("$SCHEDULE" status)"
stub systemctl 'exit 1'
[[ $("$SCHEDULE" status) == "unknown, unknown" ]] || fail "status when systemctl says nothing"
if "$SCHEDULE" sideways 2>/dev/null; then fail "an unknown action was accepted"; fi
[[ $("$AGENT" usage schedule --help) == *"on|off|status"* ]] || fail "no help"
ok
cleanup_sandbox
