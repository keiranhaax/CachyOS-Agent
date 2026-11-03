#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The features working together. Every other case tests one feature with its
# neighbours stubbed; this one runs the real chains between them through the
# dispatcher: default -> launch -> terminal, crash -> launcher, skills ->
# harnesses, accounts -> launcher, usage -> accounts -> launcher, usage ->
# widget, theme -> follow, local -> launcher, and the dispatcher's metadata
# against the units and the README. Only what lives outside this repository is
# stubbed: agent CLIs, the terminal, notify-send, journalctl, coredumpctl,
# busctl, systemctl, systemd-run, ollama, nvidia-smi, sudo and pacman, and the
# usage collectors, which reach for the network. kwriteconfig6, kreadconfig6
# and qml6 (for the widget) stay real where they are installed; a chain that
# needs one that is missing says so and does not fail.
# shellcheck disable=SC2016 # a stub's body is a script for the stub's own shell
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent

# ---- helpers ------------------------------------------------------------------

# setup: a sandbox whose PATH is its stubs, then this checkout's bin (so the
# siblings that run are these, never an installed package's), then the system.
# make_sandbox clears what could carry the real user's accounts, agents or
# settings into a chain, bar the one name below.
setup() {
  make_sandbox
  PATH=$SANDBOX/stubs:$REPO_ROOT/bin:$BASE_PATH
  unset HERMES_SESSION_SOURCE # the launcher clears it for hermes, and make_sandbox leaves it
  STATE=$XDG_STATE_HOME/cachyos-agent
  CONFIG=$XDG_CONFIG_HOME/cachyos-agent
  # A terminal window: it runs the command it is given after -e, as the real one
  # does inside its window, so what the window shows and runs can be asserted.
  stub konsole 'while (($#)) && [[ $1 != -e ]]; do shift; done; shift; "$@"'
}

# calls <stub>: the recorded calls of a stub, one per line, arguments joined by |.
calls() {
  if [[ -f $SANDBOX/calls/$1 ]]; then
    awk '$0 == "" { print line; line = ""; n = 0; next } { line = (n++ ? line "|" : "") $0 }' "$SANDBOX/calls/$1"
  fi
}

# call_n <stub> <n>: the n-th call of a stub (from 1).
call_n() { calls "$1" | sed -n "${2}p"; }

call_count() { calls "$1" | wc -l; }

# called_with <stub> <args joined by |>: whether some call of the stub had exactly those arguments.
called_with() { [[ $'\n'"$(calls "$1")"$'\n' == *$'\n'"$2"$'\n'* ]]; }

# expect <actual> <wanted> <what>
expect() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
contains() { [[ $1 == *"$2"* ]] || fail "$3: [$1] lacks [$2]"; }

# choose_default <agent>: the real `default` command, then forget the launch it
# makes, so a chain starts from a default agent and no recorded calls.
choose_default() {
  "$AGENT" default "$1" >/dev/null 2>&1
  rm -f "$SANDBOX"/calls/*
}

# eventually <command...>: retry for up to five seconds, for what a chain leaves
# running in the background.
eventually() {
  local _
  for _ in {1..100}; do
    "$@" && return 0
    sleep 0.05
  done
  return 1
}

# count_files <glob>: how many files match.
count_files() {
  local -a matches
  shopt -s nullglob
  # shellcheck disable=SC2206 # the glob is the point
  matches=($1)
  shopt -u nullglob
  echo "${#matches[@]}"
}

# files_at_least <n> <glob>: whether at least n files match.
files_at_least() { (($(count_files "$2") >= $1)); }

# ---- default, launch and prompt -----------------------------------------------

begin "default chooses an agent, launch and prompt start it unattended with the prompt intact"
setup
stub claude
[[ -z $("$AGENT" default) ]] || fail "an agent was chosen before anyone chose one"
"$AGENT" default claude 2>"$SANDBOX/window.err"
expect "$(<"$CONFIG/default-agent")" claude "the choice is not saved"
expect "$("$AGENT" default)" claude "default does not report the choice"
expect "$(call_n claude 1)" "--permission-mode|auto" "default does not start the agent in its auto mode"
expect "$(call_count konsole)" 1 "default did not open one window"
notice='cachyos-agent: starting Claude Code with --permission-mode auto, which does not stop to ask before acting'
expect "$(head -n 1 "$SANDBOX/window.err")" "$notice" "the window does not open with the unattended notice"

"$AGENT" launch --inline --prompt "hi there" 2>"$SANDBOX/inline.err"
expect "$(call_n claude 2)" "--permission-mode|auto|--|hi there" "launch --inline got the wrong argv"
expect "$(<"$SANDBOX/inline.err")" "$notice" "launch --inline does not print the notice"
expect "$(call_count konsole)" 1 "launch --inline opened a window"

# Two words: a one-word Claude prompt gets a trailing space on purpose (20-launcher covers it).
"$AGENT" prompt "fix it" 2>"$SANDBOX/window.err"
expect "$(call_count konsole)" 2 "prompt did not open a window"
terminal=$(call_n konsole 2)
[[ $terminal == "-p|tabtitle=CachyOS Agent|-e|bash|-c|"* ]] || fail "the terminal got the wrong words: $terminal"
[[ $terminal == *"|claude|--permission-mode|auto|--|fix it" ]] || fail "the terminal does not run claude with the prompt: $terminal"
contains "$terminal" "$notice" "the terminal does not carry the notice"
expect "$(call_n claude 3)" "--permission-mode|auto|--|fix it" "prompt reached claude with the wrong argv"
expect "$(head -n 1 "$SANDBOX/window.err")" "$notice" "the prompt window does not open with the notice"

# A prompt that starts with a dash, holds quotes and spans words stays one literal argument.
"$AGENT" prompt --inline -- -rf "it's \"fine\"" 2>/dev/null
expect "$(call_n claude 4)" "--permission-mode|auto|--|-rf it's \"fine\"" "a hostile-looking prompt was split or parsed"
ok
cleanup_sandbox

begin "the desktop entry explains itself while no agent is chosen and opens the default one after"
setup
stub claude
exec_line=$(sed -n 's/^Exec=//p' "$REPO_ROOT/desktop/cachyos-agent.desktop")
read -ra exec_words <<<"$exec_line"
if "${exec_words[@]}" 2>"$SANDBOX/pick.err" </dev/null; then fail "the desktop entry launched an agent with none chosen"; fi
contains "$(<"$SANDBOX/pick.err")" "No default agent" "the entry does not explain itself"
contains "$(<"$SANDBOX/pick.err")" "cachyos-agent default <name>" "the entry does not say how to choose"
contains "$(<"$SANDBOX/pick.err")" "Agents: pi omp opencode" "the entry does not list the agents"
choose_default claude
"${exec_words[@]}" 2>/dev/null </dev/null
expect "$(call_n claude 1)" "--permission-mode|auto" "the entry did not start the default agent"
expect "$(call_count konsole)" 1 "the entry did not open a window"
ok
cleanup_sandbox

begin "the shortcut binds the key to the desktop entry the repository ships"
setup
if type -P kwriteconfig6 >/dev/null && type -P kreadconfig6 >/dev/null; then
  [[ -f $REPO_ROOT/desktop/cachyos-agent.desktop ]] || fail "the shortcut names a desktop file the repository does not ship"
  "$AGENT" shortcut set >/dev/null 2>&1
  expect "$(<"$XDG_CONFIG_HOME/kglobalshortcutsrc")" $'[services][cachyos-agent.desktop]\n_launch=Meta+Ctrl+Shift+A' "the shortcut is not bound to the desktop entry"
  expect "$("$AGENT" shortcut show)" "Meta+Ctrl+Shift+A" "show does not read back what set wrote"
  "$AGENT" shortcut unset >/dev/null
  expect "$("$AGENT" shortcut show)" "not set" "unset left the shortcut bound"
  ok
else
  printf 'skip %s (kconfig is not installed)\n' "$CURRENT_TEST"
fi
cleanup_sandbox

# ---- crash diagnosis ----------------------------------------------------------

# journal_entry <uid> <comm> <pid> <exe> <signal>: a JSON line the way
# `journalctl -o json` prints a coredump record.
journal_entry() {
  jq -nc --arg uid "$1" --arg comm "$2" --arg pid "$3" --arg exe "$4" --arg sig "$5" \
    '{MESSAGE_ID: "fc2e22bc6ee647b6b90729ab34a250b1", _UID: $uid, _EXE: "/usr/lib/systemd/systemd-coredump",
      COREDUMP_COMM: $comm, COREDUMP_PID: $pid, COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: $sig}'
}

# crash_stubs: the outside of the crash chain. The prompt spans lines, which the
# argv records cannot hold, so the agent writes it to prompt.<pid> and each
# terminal window leaves a window.<pid>; the toast is delivered and answered
# "diagnose" at once, as libnotify does with --id-fd and --action.
crash_stubs() {
  stub konsole 'touch "${self%/stubs/*}/window.$$"
while (($#)) && [[ $1 != -e ]]; do shift; done; shift; "$@"'
  stub claude 'printf "%s" "${@: -1}" >"${self%/stubs/*}/prompt.$$"'
  stub coredumpctl 'echo "Mon 2026-11-02 18:41:01 EST $2 1000 1000 SIGSEGV present /usr/lib/firefox/firefox 654.1K"'
  stub journalctl 'cat "${self%/stubs/*}/journal.jsonl"'
  stub notify-send 'echo 7 >&3; echo diagnose'
  stub busctl
  stub systemd-run 'while [[ $1 != -- ]]; do shift; done; shift; exec "$@"'
}

# run_watcher: the watcher through the dispatcher, bounded in time so one that
# does not end with the journal fails instead of hanging the suite.
run_watcher() {
  timeout 20 "$AGENT" crash watch >"$SANDBOX/watch.log" 2>&1 || fail "the watcher did not end cleanly with the journal: $(<"$SANDBOX/watch.log")"
}

begin "crash hands the crash to the default agent in a terminal, with the skill's path in the prompt"
setup
stub claude
choose_default claude
crash_stubs
"$AGENT" crash 4242 comm /usr/bin/comm SIGSEGV 2>"$SANDBOX/crash.err"
expect "$(head -n 1 "$SANDBOX/crash.err")" "cachyos-agent: starting Claude Code with --permission-mode auto, which does not stop to ask before acting" "the diagnosis window does not open with the unattended notice"
expect "$(call_n coredumpctl 1)" "list|4242|--no-pager|--no-legend" "the crash time was not looked up"
expect "$(count_files "$SANDBOX/window.*")" 1 "the diagnosis did not open one window"
terminal=$(call_n konsole 1)
[[ $terminal == "-p|tabtitle=CachyOS Agent|-e|bash|-c|"* ]] || fail "the terminal got the wrong words: $terminal"
expect "$(count_files "$SANDBOX/prompt.*")" 1 "the agent did not run exactly once"
prompt=$(cat "$SANDBOX"/prompt.*)
skill=$REPO_ROOT/agents/skills/diagnose-crash/SKILL.md
[[ -f $skill ]] || fail "the diagnose-crash skill is not in the checkout"
contains "$prompt" "$skill" "the prompt does not name the skill's file"
contains "$prompt" "CachyOS machine" "the prompt does not name the machine"
for line in '  process:  comm' '  PID:      4242' '  binary:   /usr/bin/comm' '  signal:   SIGSEGV' '  time:     Mon 2026-11-02 18:41:01 EST'; do
  grep -qxF -- "$line" <<<"$prompt" || fail "the prompt has no line '$line'"
done
ok
cleanup_sandbox

begin "the watcher turns a click into one diagnosis and keeps a muted program quiet"
setup
stub claude
choose_default claude
crash_stubs
me=$(id -u)
{
  journal_entry "$me" "Web Content" 1001 /usr/lib/firefox/firefox SIGSEGV
  journal_entry "$me" mutedapp 1002 /usr/bin/mutedapp SIGABRT
  journal_entry $((me + 1)) sshd 1003 /usr/bin/sshd SIGSEGV
} >"$SANDBOX/journal.jsonl"
expect "$("$AGENT" crash mute mutedapp)" "Muted crash notifications for mutedapp." "mute did not say what is true"
run_watcher
eventually files_at_least 1 "$SANDBOX/prompt.*" || fail "the click never became a diagnosis: $(<"$SANDBOX/watch.log")"
sleep 0.5 # long enough for a diagnosis that should not happen
expect "$(count_files "$SANDBOX/prompt.*")" 1 "the agent did not run exactly once"
expect "$(call_count notify-send)" 1 "toasts sent: one expected, for firefox only"
expect "$(call_n notify-send 1 | sed 's/.*|--|//')" "Process crashed: firefox|Diagnose it with claude." "the toast does not name the crash and the default agent"
expect "$(call_count systemd-run)" 1 "the diagnosis did not start exactly once"
expect "$(call_n systemd-run 1 | sed 's/.*|--|//')" "cachyos-agent-crash|1001|Web Content|/usr/lib/firefox/firefox|SIGSEGV" "the watcher handed over the wrong crash"
expect "$(count_files "$SANDBOX/window.*")" 1 "the diagnosis did not open exactly one window"
prompt=$(cat "$SANDBOX"/prompt.*)
contains "$prompt" "  PID:      1001" "the agent was given another crash"
contains "$prompt" "  process:  Web Content" "the agent was not told the process name"
contains "$prompt" "  binary:   /usr/lib/firefox/firefox" "the agent was not told the binary"
[[ $prompt != *mutedapp* ]] || fail "the muted program reached the agent"

# Lifting the mute brings the toast, and its diagnosis, back.
rm -f "$SANDBOX"/prompt.* "$SANDBOX"/window.* "$SANDBOX"/calls/notify-send "$SANDBOX"/calls/systemd-run
journal_entry "$me" mutedapp 1002 /usr/bin/mutedapp SIGABRT >"$SANDBOX/journal.jsonl"
expect "$("$AGENT" crash mute mutedapp off)" "Crash notifications for mutedapp are back on." "unmute did not say what is true"
run_watcher
eventually files_at_least 1 "$SANDBOX/prompt.*" || fail "the unmuted crash never reached the agent: $(<"$SANDBOX/watch.log")"
expect "$(count_files "$SANDBOX/prompt.*")" 1 "the unmuted crash did not reach the agent exactly once"
contains "$(cat "$SANDBOX"/prompt.*)" "  PID:      1002" "the agent was given another crash after the unmute"
ok
cleanup_sandbox

# ---- the skills ---------------------------------------------------------------

begin "skills provision links the cachyos and diagnose-crash skills into every harness"
setup
"$AGENT" skills provision >/dev/null
for dir in .agents/skills .claude/skills .codex/skills .pi/agent/skills .gemini/config/skills .hermes/skills; do
  for skill in cachyos diagnose-crash; do
    expect "$(readlink -f "$HOME/$dir/$skill")" "$REPO_ROOT/agents/skills/$skill" "$dir/$skill is not linked to the checkout"
    [[ -f $HOME/$dir/$skill/SKILL.md ]] || fail "$dir/$skill has no SKILL.md behind the link"
  done
  [[ -f $HOME/$dir/diagnose-crash/reporting.md ]] || fail "$dir/diagnose-crash does not reach the skill's reporting guide"
done
ok
cleanup_sandbox

# ---- accounts and the launcher ------------------------------------------------

# claude_login_stub: a claude that signs in as FIX_ID / FIX_EMAIL when asked to
# log in, writing the files the real CLI writes, and otherwise prints which
# account home it was started with.
claude_login_stub() {
  stub claude 'if [[ ${1-} == auth && ${2-} == login ]]; then
  home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  account_file=$home/.claude.json
  [[ -n ${CLAUDE_CONFIG_DIR:-} ]] || account_file=$HOME/.claude.json
  mkdir -p "$home"
  printf "{\"oauthAccount\":{\"accountUuid\":\"%s\",\"emailAddress\":\"%s\",\"organizationName\":\"Org\"}}\n" "$FIX_ID" "$FIX_EMAIL" >"$account_file"
  printf "{\"claudeAiOauth\":{\"accessToken\":\"SECRET-ACCESS\",\"refreshToken\":\"SECRET-REFRESH\",\"rateLimitTier\":\"default_claude_max_5x\",\"subscriptionType\":\"max\"}}\n" >"$home/.credentials.json"
else
  printf "CLAUDE_CONFIG_DIR=%s\nCACHYOS_AGENT_CLAUDE_HOME=%s\n" "${CLAUDE_CONFIG_DIR-unset}" "${CACHYOS_AGENT_CLAUDE_HOME-unset}"
fi'
}

# refreshed_at_least <n>: whether the usage refresh stub has been started n times.
refreshed_at_least() { (($(call_count cachyos-agent-usage-update) >= $1)); }

# two_accounts: Main and Work signed in through the real add command, with the
# usage refresh that add and use trigger stubbed out (a later chain runs the
# real one) and the private browser the CLI would open not found.
two_accounts() {
  claude_login_stub
  stub cachyos-agent-usage-update
  stub xdg-settings 'exit 1'
  FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add claude >/dev/null
  FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude Work >/dev/null
  # Each add refreshes the usage record in the background; let both finish
  # starting before a chain replaces the stub, or the real command would run.
  eventually refreshed_at_least 2 || fail "adding accounts did not refresh the usage record twice"
}

begin "account use makes launch run the agent in that account's home, and use main puts it back"
setup
two_accounts
expect "$(<"$CONFIG/default-agent")" claude "the first sign-in did not become the default agent"
expect "$(jq -r '.[0].accounts | map(.id) | join(",")' <<<"$("$AGENT" account list claude --json)")" "main,work" "the accounts are not both registered"
work_home=$STATE/accounts/claude/work
[[ -f $work_home/.credentials.json ]] || fail "the added account has no home of its own"
expect "$(calls cachyos-agent-usage-update | sort -u)" "--force|claude" "adding accounts did not refresh the usage record"

expect "$("$AGENT" launch --inline 2>/dev/null)" $'CLAUDE_CONFIG_DIR=unset\nCACHYOS_AGENT_CLAUDE_HOME=' "Main is not the account that launches"
"$AGENT" account use work >/dev/null 2>&1
eventually called_with cachyos-agent-usage-update "--limits-only|claude" || fail "switching accounts did not refresh the usage record's limits"
expect "$("$AGENT" launch --inline 2>/dev/null)" "CLAUDE_CONFIG_DIR=$work_home
CACHYOS_AGENT_CLAUDE_HOME=$work_home" "launch does not run claude in Work's home"
expect "$(bash -c 'source "$1"; cx' _ "$REPO_ROOT/shell/cachyos-agent.bash")" "CLAUDE_CONFIG_DIR=$work_home
CACHYOS_AGENT_CLAUDE_HOME=$work_home" "the cx alias does not follow the selected account"
out=$(CLAUDE_CONFIG_DIR=/explicit "$AGENT" launch --inline 2>/dev/null)
expect "${out%%$'\n'*}" "CLAUDE_CONFIG_DIR=/explicit" "an explicit CLAUDE_CONFIG_DIR does not beat the selection"
"$AGENT" account use main >/dev/null 2>&1
expect "$("$AGENT" launch --inline 2>/dev/null)" $'CLAUDE_CONFIG_DIR=unset\nCACHYOS_AGENT_CLAUDE_HOME=' "use main did not clear the account"
ok
cleanup_sandbox


# ---- usage and accounts -------------------------------------------------------

# usage_collector <main> <work>: a stand-in for the Claude collector. It prints
# the record of Claude Code with Main at <main> and Work at <work> (fractions of
# a window that resets in three hours), marking as active the account the
# registry says is, as the real collector does.
usage_collector() {
  jq -nc --arg reset "$(date -u -d '+3 hours 30 seconds' +%Y-%m-%dT%H:%M:%SZ)" --argjson main "$1" --argjson work "$2" '
    def window($p): {label: "Session (5-hour)", percent: $p, resetsAt: $reset};
    {schemaVersion: 1, id: "claude", name: "Claude Code", ready: true, tierLabel: "max 5x",
     updatedAt: (now | floor | todate), limits: [window($main)], limitsStale: false, limitsFetchedAt: 0,
     usageStatusText: "", authHelpText: "", hasLocalStats: true, todayTotalTokens: 1234567,
     recentDays: [{date: "2026-11-02", messageCount: 3300000}],
     accounts: [{id: "main", label: "Main", plan: "Max 5x", limits: [window($main)]},
                {id: "work", label: "Work", plan: "Max 5x", limits: [window($work)]}]}' >"$SANDBOX/record.json"
  stub cachyos-agent-usage-claude 'registry=$XDG_STATE_HOME/cachyos-agent/accounts/claude.json
active=main
if [[ -f $registry ]]; then active=$(jq -r .active "$registry"); fi
jq -c --arg active "$active" "if .accounts then .accounts |= map(.active = (.id == \$active)) else . end" "${self%/stubs/*}/record.json"'
}

begin "usage update writes the records the report and the widget read, with or without accounts"
setup
usage_collector 0.42 0.1
[[ ! -e $STATE/accounts ]] || fail "the sandbox starts with accounts"
"$AGENT" usage update claude 2>"$SANDBOX/update.err"
[[ ! -s $SANDBOX/update.err ]] || fail "update said something with no accounts: $(<"$SANDBOX/update.err")"
expect "$(call_count cachyos-agent-usage-claude)" 1 "the collector did not run exactly once"
expect "$(jq -S 'del(.accounts)' "$STATE/usage/claude.json")" "$(jq -S 'del(.accounts)' "$SANDBOX/record.json")" "the record was not written as the collector printed it"
[[ ! -e $STATE/accounts ]] || fail "update created account state of its own"
report=$("$AGENT" usage)
contains "$report" "Claude Code  Max 5x" "the report does not name the agent and its plan"
[[ $report =~ Session\ \(5-hour\)\ +42%\ +resets\ in\ 3h ]] || fail "the report does not show the limit window: $report"
jq -e 'type == "array" and length == 1 and .[0].id == "claude" and .[0].limits[0].percent == 0.42' <<<"$("$AGENT" usage --json)" >/dev/null \
  || fail "usage --json is not the array of records"

# A filter has something to leave out only when a second agent has a record.
jq -nc '{schemaVersion: 1, id: "codex", name: "Codex", ready: true, tierLabel: "plus", updatedAt: (now | floor | todate),
         limits: [{label: "Weekly", percent: 0.5, resetsAt: (now + 86400 | floor | todate)}]}' >"$STATE/usage/codex.json"
everything=$("$AGENT" usage)
contains "$everything" "Claude Code" "the report with two records lacks Claude Code"
contains "$everything" "Codex" "the report with two records lacks Codex"
expect "$("$AGENT" usage -- claude)" "$report" "usage -- claude is not the report of Claude Code alone"
jq -e 'map(.id) == ["claude", "codex"]' <<<"$("$AGENT" usage --json)" >/dev/null || fail "usage --json does not list both records"
jq -e 'map(.id) == ["claude"]' <<<"$("$AGENT" usage --json claude)" >/dev/null || fail "usage --json claude did not filter"
jq -e 'map(.id) == ["codex"]' <<<"$("$AGENT" usage --json codex)" >/dev/null || fail "usage --json codex did not filter"
ok
cleanup_sandbox

begin "usage update drives the account autoswitch, and launch and account list follow it"
setup
two_accounts
rm -f "$SANDBOX/stubs/cachyos-agent-usage-update" "$SANDBOX"/calls/*
hash -r
# The provider is left out: the default agent, Claude, stands for it.
expect "$("$AGENT" account mode auto 90)" "Claude switches new sessions to the account with the most headroom at 90%." "account mode did not say what is true"
usage_collector 0.97 0.12
"$AGENT" usage update claude 2>"$SANDBOX/update.err" || fail "update failed with accounts: $(<"$SANDBOX/update.err")"
expect "$(jq -r '.[0].active' <<<"$("$AGENT" account list claude --json)")" work "Main at 97% did not switch to Work"
contains "$(<"$SANDBOX/update.err")" "New Claude sessions now use Work" "the switch was not announced"
expect "$(call_count cachyos-agent-usage-claude)" 2 "the collector was not run again for the new account"
expect "$(call_n cachyos-agent-usage-claude 2)" "--limits-only" "the second run did not ask only for the limits"
work_home=$STATE/accounts/claude/work
expect "$("$AGENT" launch --inline 2>/dev/null)" "CLAUDE_CONFIG_DIR=$work_home
CACHYOS_AGENT_CLAUDE_HOME=$work_home" "launch does not follow the autoswitch"
# The record's per-account limits show up in the account listing.
jq -e '.[0].accounts | map({(.id): .limits[0].percent}) | add == {main: 0.97, work: 0.12}' <<<"$("$AGENT" account list claude --json)" >/dev/null \
  || fail "account list does not carry the limits of the usage record: $("$AGENT" account list claude --json)"
listing=$("$AGENT" account list claude)
[[ $listing =~ \*\ +work\ +Work\ +Max\ 5x\ +work@example.com\ +Session\ \(5-hour\):\ 12% ]] || fail "the listing does not mark Work active with its limit: $listing"
report=$("$AGENT" usage)
[[ $report =~ Accounts ]] && [[ $report =~ Main\ +Max\ 5x ]] && [[ $report =~ Work\ +Max\ 5x\ +\(active\) ]] || fail "the report does not show both accounts with Work active: $report"

# Work has room and Main does not: another update leaves the choice where it is.
"$AGENT" usage update claude 2>/dev/null
expect "$(jq -r '.[0].active' <<<"$("$AGENT" account list claude --json)")" work "a second update switched the account again"
ok
cleanup_sandbox

# widget_json: the widget's main.qml run headless by test/plasmoid/app.qml, with
# the real data engine running the real cachyos-agent, and what it shows as JSON.
widget_json() {
  local log=$SANDBOX/qml.log
  QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 60 \
    qml6 -I "$REPO_ROOT/test/plasmoid/stubs" "$REPO_ROOT/test/plasmoid/app.qml" -- \
    "$REPO_ROOT/plasmoid/org.cachyos.agent/contents/ui/main.qml" dump "" >"$log" 2>&1 || fail "qml6 failed: $(head -c 600 "$log")"
  sed -n 's/^qml: RESULT //p' "$log"
}

begin "the widget shows what usage update wrote, read through usage --json"
setup
engine=/usr/lib/qt6/plugins/plasma5support/dataengine/plasma_engine_executable.so
if type -P qml6 >/dev/null && [[ -f $engine && -d /usr/lib/qt6/qml/org/kde/plasma/plasma5support && -d /usr/lib/qt6/qml/org/kde/plasma/extras ]]; then
  usage_collector 0.42 0.1
  jq -c 'del(.accounts)' "$SANDBOX/record.json" >"$SANDBOX/record.new" && mv "$SANDBOX/record.new" "$SANDBOX/record.json"
  "$AGENT" usage update claude
  shown=$(widget_json)
  jq -e '.loaded and .problem == "" and ([.agents[].name] == ["Claude Code"]) and .tooltip == "Claude Code 42%" and .page.bars == [0.42] and .page.notPlain == []' <<<"$shown" >/dev/null \
    || fail "the widget does not show the record: $shown"
  jq -e '.page.texts | index("Max 5x") and index("Session (5-hour)") and index("42%  ·  resets in 3h 0m") and index("Tokens: 1.2M today, 3.3M this week")' <<<"$shown" >/dev/null \
    || fail "the widget lacks the plan, the limit or the tokens: $shown"

  # Several accounts: the widget lists them, as the registry-less record names them.
  usage_collector 0.42 0.1
  "$AGENT" usage update claude
  shown=$(widget_json)
  jq -e '.loaded and .problem == "" and (.page.texts | any(startswith("Main")) and any(startswith("Work")))' <<<"$shown" >/dev/null \
    || fail "the widget does not list both accounts: $shown"
  ok
else
  printf 'UNVERIFIED %s: qml6, the Plasma executable data engine or the Plasma QML modules are not installed\n' "$CURRENT_TEST"
fi
cleanup_sandbox

# ---- theme --------------------------------------------------------------------

# plasma_scheme <bg> <fg> <window-bg> <selection-bg>: a kdeglobals with the
# groups the palette reads, in KDE's "r,g,b" syntax.
plasma_scheme() {
  mkdir -p "$XDG_CONFIG_HOME"
  {
    printf '[Colors:View]\nBackgroundNormal=%s\nForegroundNormal=%s\n' "$1" "$2"
    printf 'ForegroundNegative=218,68,83\nForegroundPositive=39,174,96\nForegroundNeutral=246,116,0\n'
    printf 'ForegroundActive=61,174,233\nForegroundLink=29,153,243\nForegroundVisited=155,89,182\n'
    printf 'DecorationFocus=61,174,233\n[Colors:Window]\nBackgroundNormal=%s\n' "$3"
    printf '[Colors:Selection]\nBackgroundNormal=%s\nForegroundNormal=252,252,252\n' "$4"
  } >"$XDG_CONFIG_HOME/kdeglobals"
}

begin "theme sync renders the Plasma scheme into Hermes and Claude Code, and follows a change of scheme"
setup
if type -P kreadconfig6 >/dev/null; then
  stub hermes
  mkdir -p "$HOME/.hermes" "$HOME/.claude"
  : >"$HOME/.hermes/config.yaml"
  plasma_scheme 20,22,24 252,252,252 32,35,38 61,174,233
  palette=$("$AGENT" theme palette)
  contains "$palette" $'background\t#141618' "the palette does not carry the scheme's background"
  contains "$palette" $'theme_type\tdark' "the palette does not call the scheme dark"

  sync=$("$AGENT" theme sync) || fail "theme sync failed: $sync"
  contains "$sync" "hermes: wrote $HOME/.hermes/skins/cachyos.yaml" "Hermes was not published to"
  contains "$sync" "claude: wrote $HOME/.claude/themes/cachyos.json" "Claude Code was not published to"
  contains "$sync" "pi: skipped" "an agent that is not here was given a theme"
  grep -qx '  background: "#141618"' "$HOME/.hermes/skins/cachyos.yaml" || fail "the Hermes skin does not hold the scheme's background"
  jq -e '.base == "dark" and .overrides.text == "#fcfcfc"' "$HOME/.claude/themes/cachyos.json" >/dev/null \
    || fail "the Claude theme does not hold the scheme: $(<"$HOME/.claude/themes/cachyos.json")"
  expect "$(call_count hermes)" 0 "a plain sync switched Hermes' skin"
  [[ ! -e $HOME/.claude/settings.json ]] || fail "a plain sync switched Claude's theme"
  contains "$("$AGENT" theme sync)" "unchanged $HOME/.hermes/skins/cachyos.yaml" "syncing the same scheme again rewrote the skin"

  # The scheme changes (Breeze Light); the next sync follows.
  plasma_scheme 255,255,255 35,38,41 239,240,241 61,174,233
  "$AGENT" theme sync >/dev/null
  grep -qx '  background: "#ffffff"' "$HOME/.hermes/skins/cachyos.yaml" || fail "the Hermes skin did not follow the new scheme"
  jq -e '.base == "light"' "$HOME/.claude/themes/cachyos.json" >/dev/null || fail "the Claude theme did not follow the new scheme"

  printf '{"model":"opus","theme":"dark"}\n' >"$HOME/.claude/settings.json"
  "$AGENT" theme sync --activate --only hermes,claude >/dev/null
  jq -e '.theme == "custom:cachyos" and .model == "opus"' "$HOME/.claude/settings.json" >/dev/null || fail "--activate lost a setting or did not set the theme"
  expect "$(call_n hermes 1)" "skin|use|cachyos" "--activate did not switch Hermes' skin"
  ok
else
  printf 'skip %s (kconfig is not installed)\n' "$CURRENT_TEST"
fi
cleanup_sandbox

begin "theme follow generates units for the checkout that run the sync, and off removes them"
setup
# theme follow refuses a checkout whose path would need escaping in an ExecStart=
# line (bin/cachyos-agent-theme-follow, generate_units), so there is nothing to
# generate from one: a developer's ~/My Code or a build directory with an @ in it.
if ! type -P kreadconfig6 >/dev/null; then
  printf 'skip %s (kconfig is not installed)\n' "$CURRENT_TEST"
elif [[ ! $REPO_ROOT/bin =~ ^[A-Za-z0-9/._+-]+$ ]]; then
  printf 'skip %s (theme follow does not generate units for the checkout at %s)\n' "$CURRENT_TEST" "$REPO_ROOT"
else
  stub systemctl 'case ${2-} in is-enabled) echo enabled ;; is-active) echo active ;; esac'
  export CACHYOS_AGENT_SYSTEM_UNIT_DIR=$SANDBOX/no-packaged-units
  units=$XDG_CONFIG_HOME/systemd/user
  "$AGENT" theme follow on >/dev/null
  for unit in cachyos-agent-theme-sync.path cachyos-agent-theme-sync.service; do
    [[ -s $units/$unit ]] || fail "$unit was not generated"
  done
  service_exec=$(sed -n 's/^ExecStart=//p' "$units/cachyos-agent-theme-sync.service")
  expect "$service_exec" "$REPO_ROOT/bin/cachyos-agent-theme-sync" "the service does not run this checkout's sync"
  contains "$(<"$units/cachyos-agent-theme-sync.path")" "PathModified=%E/kdeglobals" "the path unit does not watch kdeglobals"
  expect "$(calls systemctl | tr '\n' ' ')" "--user|daemon-reload --user|enable|--now|cachyos-agent-theme-sync.path " "follow on called systemctl wrongly"
  expect "$("$AGENT" theme follow status)" "theme follow: on (enabled, active)" "status does not say it follows"

  # What systemd does when the path unit fires: run the service's command.
  mkdir -p "$HOME/.claude"
  plasma_scheme 20,22,24 252,252,252 32,35,38 61,174,233
  timeout 20 "$service_exec" >/dev/null || fail "the generated service's command failed"
  [[ -s $HOME/.claude/themes/cachyos.json ]] || fail "the generated service's command did not sync"

  "$AGENT" theme follow off >/dev/null
  [[ ! -e $units/cachyos-agent-theme-sync.path && ! -e $units/cachyos-agent-theme-sync.service ]] || fail "follow off left the generated units"
  contains "$(calls systemctl | tr '\n' ' ')" "--user|disable|--now|cachyos-agent-theme-sync.path" "follow off did not disable the path unit"
  unset CACHYOS_AGENT_SYSTEM_UNIT_DIR
  ok
fi
cleanup_sandbox

# ---- local models and the launcher --------------------------------------------

# local_machine: a machine with no GPU and 64 GiB of RAM, and an Ollama that
# keeps the models it was told to pull and create in $SANDBOX/models.list.
local_machine() {
  printf 'MemTotal:       %d kB\n' $((64 * 1048576)) >"$SANDBOX/meminfo"
  mkdir -p "$SANDBOX/drm" "$SANDBOX/models"
  export CACHYOS_AGENT_MEMINFO=$SANDBOX/meminfo CACHYOS_AGENT_DRM_DIR=$SANDBOX/drm CACHYOS_AGENT_MODELS_DIR=$SANDBOX/models
  stub nvidia-smi 'exit 9'
  stub df 'printf "%s\n" Avail 9999999999999'
  stub sudo 'exec "$@"'
  stub systemctl 'case ${1-} in is-active) exit 0 ;; esac'
  stub pacman
  stub ollama 'list=${self%/stubs/*}/models.list
case $1 in
  list) echo "NAME ID SIZE MODIFIED"; if [[ -f $list ]]; then sed "s/\$/ x 1 GB now/" "$list"; fi ;;
  pull) echo "$2" >>"$list" ;;
  create) echo "$2:latest" >>"$list"; cp "$4" "${self%/stubs/*}/modelfile" ;;
  rm) grep -vxF -e "$2" -e "$2:latest" "$list" >"$list.new" || true; mv "$list.new" "$list" ;;
esac'
}

begin "local use pulls and records a model, and launch --local points OpenCode or Pi at it"
setup
local_machine
stub opencode 'if [[ ${1-} == --version ]]; then echo 2.2.5; else printf "%s" "$OPENCODE_CONFIG_CONTENT"; fi'
stub pi 'printf "%s %s\n" "$CACHYOS_AGENT_LOCAL_MODEL" "$CACHYOS_AGENT_LOCAL_URL"'
out=$("$AGENT" local use ornith-9b 2>&1) || fail "local use failed: $out"
expect "$(<"$STATE/local/active")" ornith-9b "use did not record the model"
contains "$out" "cachyos-agent launch --local" "use does not say how to launch"
contains "$out" "http://127.0.0.1:11434/v1" "use does not say where the endpoint is"
expect "$(call_n ollama 3)" "pull|ornith:9b" "the model was not pulled"
expect "$(call_n ollama 4 | cut -d'|' -f1-2)" "create|ornith-9b" "the model was not created under the recipe's name"
expect "$(<"$SANDBOX/modelfile")" $'FROM ornith:9b\nPARAMETER num_ctx 32768' "the model was not given the recipe's context"
expect "$(call_count sudo)" 0 "use asked for privileges although nothing needed them"

choose_default opencode
config=$("$AGENT" launch --local --inline 2>/dev/null)
jq -e '.model == "ollama/ornith-9b" and .provider.ollama.options.baseURL == "http://127.0.0.1:11434/v1" and (.provider.ollama.models | has("ornith-9b"))' <<<"$config" >/dev/null \
  || fail "OpenCode was not configured for the local model: $config"
expect "$(call_n opencode 2)" "--auto|--standalone" "OpenCode was not started in its auto mode on a private service"

choose_default pi
expect "$("$AGENT" launch --local --inline 2>/dev/null)" "ornith-9b http://127.0.0.1:11434/v1" "Pi did not get the model and endpoint"
expect "$(call_n pi 1)" "--extension|$REPO_ROOT/data/pi-ollama.ts|--provider|ollama|--model|ornith-9b" "Pi was not pointed at the local provider"
[[ -f $REPO_ROOT/data/pi-ollama.ts ]] || fail "the extension the launcher loads is not shipped"

# An agent that cannot be pointed at a local model gives way to one that can.
stub claude
choose_default claude
"$AGENT" launch --local --inline >/dev/null 2>&1
expect "$(call_count claude)" 0 "launch --local ran an agent that cannot use the local model"
expect "$(call_count pi)" 1 "launch --local did not fall back to Pi"

"$AGENT" local remove ornith-9b >/dev/null
[[ ! -e $STATE/local/active ]] || fail "remove left the model active"
if out=$("$AGENT" launch --local --inline 2>&1 </dev/null); then fail "launch --local ran with no model chosen"; fi
contains "$out" "cachyos-agent local use" "launch --local does not say how to choose a model"
ok
cleanup_sandbox

# ---- the dispatcher against the units -----------------------------------------------

begin "commands --check passes, every group is described, and every visible command answers --help"
setup
out=$("$AGENT" commands --check 2>&1) || fail "commands --check failed: $out"
[[ $out =~ ^commands\ ok:\ [0-9]+$ ]] || fail "commands --check said: $out"
all=$("$AGENT" commands --json --all)
jq -e '.ok == true and (.commands | length) > 0' <<<"$all" >/dev/null || fail "commands --json is not ok"
groups=$(jq -r '.commands | map(.group) | unique[]' <<<"$all"; printf 'commands\nversion\n')
usage_text=$("$AGENT" --help)
for group in $groups; do
  line=$(grep -E "^  $group +" <<<"$usage_text") || fail "the group $group is not in the usage text"
  [[ $line != *"  $group commands" ]] || fail "the group $group has no description in the dispatcher"
done
# Every visible command answers --help without doing its work.
while IFS= read -r route; do
  read -ra words <<<"${route#cachyos-agent }"
  help=$("$AGENT" "${words[@]}" --help 2>&1 </dev/null) || fail "'$route --help' failed: $help"
  [[ -n $help ]] || fail "'$route --help' printed nothing"
done < <(jq -r '.commands[] | select(.hidden | not) | .route' <<<"$all")
ok
cleanup_sandbox

begin "every unit file is well formed, runs a command the package ships, and loads in systemd"
setup
units=$REPO_ROOT/systemd/user
mkdir "$SANDBOX/units"
# The packaged units name /usr/bin; systemd is shown this checkout's commands
# instead, through a link, so a checkout path with a space in it does not split
# the ExecStart= line.
ln -s "$REPO_ROOT/bin" "$SANDBOX/shipped-bin"
shopt -s nullglob
unit_files=("$units"/*.service "$units"/*.timer "$units"/*.path)
shopt -u nullglob
((${#unit_files[@]} >= 5)) || fail "expected the crash, theme and usage units, found ${#unit_files[@]}"
for file in "${unit_files[@]}"; do
  name=${file##*/}
  base=${name%.*}
  case $name in
    *.service) section=Service ;;
    *.timer) section=Timer ;;
    *.path) section=Path ;;
  esac
  grep -qx '\[Unit\]' "$file" || fail "$name has no [Unit] section"
  grep -qx "\[$section\]" "$file" || fail "$name has no [$section] section"
  grep -q '^Description=.' "$file" || fail "$name has no description"
  # A service that a timer or a path unit starts needs no install section of its own; any other does.
  if [[ $section != Service || ! -f $units/$base.timer && ! -f $units/$base.path ]]; then
    grep -qx '\[Install\]' "$file" || fail "$name is started by nothing and has no [Install] section"
  fi
  if [[ $section == Service ]]; then
    exec_line=$(grep '^ExecStart=' "$file") || fail "$name has no ExecStart"
    command_path=${exec_line#ExecStart=}
    [[ $command_path == /usr/bin/cachyos-agent-* ]] || fail "$name does not run an absolute /usr/bin/cachyos-agent-* command: $exec_line"
    [[ -x $REPO_ROOT/bin/${command_path##*/} ]] || fail "$name runs ${command_path##*/}, which the package does not ship"
  fi
  sed "s|^ExecStart=/usr/bin/|ExecStart=$SANDBOX/shipped-bin/|" "$file" >"$SANDBOX/units/$name"
done
if type -P systemd-analyze >/dev/null; then
  verdict=$(cd "$SANDBOX/units" && systemd-analyze --user verify ./* 2>&1 || true)
  [[ $verdict != *cachyos-agent* ]] || fail "systemd rejects a unit: $verdict"
else
  printf 'note %s: systemd-analyze is not installed, so only the sections and commands were checked\n' "$CURRENT_TEST"
fi
ok
cleanup_sandbox
