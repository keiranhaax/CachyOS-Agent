#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The subscription account commands (add, use, list, remove, rename, mode, and
# the hidden home, exec and state) and the registry engine behind them, run
# through the dispatcher against stubbed provider CLIs that write the same
# credential files the real ones do.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent

# `account add` asks for a label when its stdin is a terminal. The case would then
# depend on how it was started: from a keyboard it stops at the first prompt, and
# makepkg's check() runs it with the stdin it inherited. Cases that want a terminal
# get one from script(1) below.
exec </dev/null

# The stubs sign in as whoever FIX_ID and FIX_EMAIL name when they run, so one
# test plays several accounts. FIX_NOLOGIN makes a login that writes nothing.
# FIX_TIER and FIX_SUB set what Claude's credentials say of the plan, and
# FIX_LOGINFAIL makes the CLI's login end with an error.
# Each login appends what it saw to $SANDBOX/logins.
# shellcheck disable=SC2016 # a program for the stub's own bash, expanded when it runs
CLAUDE_STUB='
if [[ ${1-} == auth && ${2-} == login ]]; then
  browser=no; [[ -z ${BROWSER:-} ]] || browser=yes
  echo "claude CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR-unset} browser=$browser" >>"$SANDBOX/logins"
  [[ -z ${FIX_LOGINFAIL:-} ]] || exit 1
  if [[ -z ${FIX_NOLOGIN:-} ]]; then
    home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
    account_file=$home/.claude.json
    [[ -n ${CLAUDE_CONFIG_DIR:-} ]] || account_file=$HOME/.claude.json
    mkdir -p "$home"
    printf "{\"oauthAccount\":{\"accountUuid\":\"%s\",\"emailAddress\":\"%s\",\"organizationName\":\"Org\"}}\n" "$FIX_ID" "$FIX_EMAIL" >"$account_file"
    printf "{\"claudeAiOauth\":{\"accessToken\":\"SECRET-ACCESS\",\"refreshToken\":\"SECRET-REFRESH\",\"rateLimitTier\":\"%s\",\"subscriptionType\":\"%s\"}}\n" "${FIX_TIER:-default_claude_max_5x}" "${FIX_SUB:-max}" >"$home/.credentials.json"
  fi
  if [[ -n ${BROWSER:-} ]]; then "$BROWSER" https://claude.ai/oauth; fi
else
  printf "CLAUDE_CONFIG_DIR=%s\nCACHYOS_AGENT_CLAUDE_HOME=%s\nargs=%s\n" "${CLAUDE_CONFIG_DIR-unset}" "${CACHYOS_AGENT_CLAUDE_HOME-unset}" "$*"
fi'

# shellcheck disable=SC2016 # a program for the stub's own bash, expanded when it runs
CODEX_STUB='
if [[ ${1-} == login ]]; then
  echo "codex CODEX_HOME=${CODEX_HOME-unset}" >>"$SANDBOX/logins"
  home=${CODEX_HOME:-$HOME/.codex}
  mkdir -p "$home"
  claims=$(printf "{\"email\":\"%s\",\"https://api.openai.com/auth\":{\"chatgpt_plan_type\":\"plus\"}}" "$FIX_EMAIL" | base64 -w0 | tr "+/" "-_" | tr -d "=")
  printf "{\"tokens\":{\"account_id\":\"%s\",\"id_token\":\"h.%s.s\"}}\n" "$FIX_ID" "$claims" >"$home/auth.json"
else
  printf "CODEX_HOME=%s\nCACHYOS_AGENT_CODEX_HOME=%s\nargs=%s\n" "${CODEX_HOME-unset}" "${CACHYOS_AGENT_CODEX_HOME-unset}" "$*"
fi'

# shellcheck disable=SC2016 # a program for the stub's own bash, expanded when it runs
GROK_STUB='
if [[ ${1-} == login ]]; then
  echo "grok GROK_HOME=${GROK_HOME-unset}" >>"$SANDBOX/logins"
  home=${GROK_HOME:-$HOME/.grok}
  mkdir -p "$home"
  printf "{\"https://auth.x.ai::k\":{\"user_id\":\"%s\",\"email\":\"%s\"}}\n" "$FIX_ID" "$FIX_EMAIL" >"$home/auth.json"
else
  printf "GROK_HOME=%s\nCACHYOS_AGENT_GROK_HOME=%s\nargs=%s\n" "${GROK_HOME-unset}" "${CACHYOS_AGENT_GROK_HOME-unset}" "$*"
fi'

# setup: a sandbox where claude, codex and grok are the stubs above, the
# default browser is Brave (a stub), and the usage collector is a stub too: the
# usage feature's real one rewrites $STATE/usage/*.json on its own schedule,
# over the records a case writes by hand, and would reach for the network.
# $STATE is where the commands keep their state.
setup() {
  make_sandbox
  export SANDBOX
  STATE=$XDG_STATE_HOME/cachyos-agent
  : >"$SANDBOX/logins"
  stub cachyos-agent-usage-update
  stub claude "$CLAUDE_STUB"
  stub codex "$CODEX_STUB"
  stub grok "$GROK_STUB"
  stub brave
  stub xdg-settings 'echo brave-browser.desktop'
  export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$SANDBOX/share
  mkdir -p "$XDG_DATA_HOME/applications"
  printf '[Desktop Entry]\nName=Brave\nExec=brave %%U\n\n[Desktop Action private]\nExec=brave --incognito\n' \
    >"$XDG_DATA_HOME/applications/brave-browser.desktop"
}

# sign_in <provider> <id> <email> [label]: sign in as that account through the
# real add command, the first time as the primary login.
sign_in() {
  local provider=$1 id=$2 email=$3
  shift 3
  FIX_ID=$id FIX_EMAIL=$email "$AGENT" account add "$provider" "$@" >/dev/null
}

# registry <provider> <jq filter>
registry() {
  jq -r "$2" "$STATE/accounts/$1.json"
}

# eventually <command...>: retry for up to five seconds, for what the commands
# leave running in the background.
eventually() {
  for _ in {1..100}; do
    "$@" && return 0
    sleep 0.05
  done
  return 1
}

# gone <pid>: whether that process has ended.
gone() {
  ! kill -0 "$1" 2>/dev/null
}

# called <stub> <text>: whether the stub's recorded arguments contain the text.
called() {
  [[ -f $SANDBOX/calls/$1 ]] && grep -qF -- "$2" "$SANDBOX/calls/$1"
}

# ---- add ---------------------------------------------------------------------

begin "the first sign-in uses the normal browser, registers the login as Main and becomes the default agent"
setup
out=$(FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add claude)
[[ $out == *"Signed in to Claude."* ]] || fail "no confirmation: $out"
[[ $(<"$SANDBOX/logins") == "claude CLAUDE_CONFIG_DIR=unset browser=no" ]] || fail "the login did not run in the CLI's own home with the normal browser: $(<"$SANDBOX/logins")"
[[ $(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent") == claude ]] || fail "the first signed-in agent did not become the default"
jq -e '.[0].accounts | length == 1 and (.[0] | .id == "main" and .primary and .signedIn and .email == "main@example.com" and .plan == "Max 5x")' \
  <<<"$("$AGENT" account list claude --json)" >/dev/null || fail "Main is not listed as the signed-in primary"
FIX_ID=u-codex FIX_EMAIL=codex@example.com "$AGENT" account add codex >/dev/null
[[ $(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent") == claude ]] || fail "a later sign-in replaced the default agent"
ok
cleanup_sandbox

begin "an additional account signs in privately in a home of its own that shares the primary's settings"
setup
sign_in claude u-main main@example.com
printf '{"theme":"light","mcpServers":{"fs":{}},"oauthAccount":{"accountUuid":"u-main","emailAddress":"main@example.com"}}\n' >"$HOME/.claude.json"
out=$(FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude Work)
[[ $out == *"Added Work (work@example.com)."* && $out == *"cachyos-agent account use claude work"* ]] || fail "no confirmation with the next step: $out"
[[ $out == *"private window that opens"* ]] || fail "the private window was not announced: $out"
login=$(tail -n1 "$SANDBOX/logins")
[[ $login == "claude CLAUDE_CONFIG_DIR=$STATE/accounts/claude/.pending/login-"*" browser=yes" ]] || fail "the login did not run in a pending home with a private browser: $login"
home=$STATE/accounts/claude/work
[[ $(registry claude '[.accounts[].id] | join(",")') == main,work ]] || fail "registry accounts: $(registry claude '.accounts')"
[[ $(registry claude '[.active, .switch, .threshold, .alert] | join(",")') == "main,manual,95," ]] || fail "registry defaults changed"
[[ $(registry claude '.accounts[1] | [.home, .primary, .accountId, .email, .plan] | join(",")') == "$home,false,u-work,work@example.com,Max 5x" ]] \
  || fail "the new account entry is wrong: $(registry claude '.accounts[1]')"
[[ -f $home/.credentials.json && ! -e $home/.cachyos-agent-login.json ]] || fail "the home lacks its credentials or keeps its login receipt"
[[ $(jq -r '.mcpServers | keys[0]' "$home/.claude.json") == fs && $(jq -r .theme "$home/.claude.json") == light ]] \
  || fail "the primary's MCP servers and theme did not carry over"
[[ $(readlink "$home/settings.json") == "$HOME/.claude/settings.json" && $(readlink "$home/projects") == "$HOME/.claude/projects" && -d $HOME/.claude/projects ]] \
  || fail "the shared settings and history are not linked to the primary home"
[[ -z $(ls -A "$STATE/accounts/claude/.pending") ]] || fail "a pending login home was left behind"
eventually called brave "--incognito" || fail "the login page did not open in a private Brave window"
[[ $(<"$SANDBOX/calls/brave") == "--incognito
https://claude.ai/oauth" ]] || fail "Brave got the wrong arguments: $(<"$SANDBOX/calls/brave")"
! compgen -G "$XDG_RUNTIME_DIR/cachyos-agent-browser.*" >/dev/null || fail "the browser script was left behind"
eventually called cachyos-agent-usage-update "--force" || fail "the usage record was not refreshed"
! grep -rq "SECRET-" "$STATE/accounts/claude.json" || fail "a token reached the registry"
[[ $(stat -c %a "$STATE/accounts/claude.json") == 600 && $(stat -c %a "$STATE/accounts") == 700 && $(stat -c %a "$home") == 700 ]] \
  || fail "registry, accounts directory or home is not private"
ok
cleanup_sandbox

begin "the label is optional and defaults to the email's name"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com
[[ $(registry claude '.accounts[1] | .id + "/" + .label') == work/work ]] || fail "unnamed account: $(registry claude '.accounts[1]')"
sign_in claude u-side side@example.com Side project
[[ $(registry claude '.accounts[2] | .id + "/" + .label') == "side-project/Side project" ]] || fail "multi-word label: $(registry claude '.accounts[2]')"
ok
cleanup_sandbox

begin "signing in as an account that is already here is refused and leaves nothing behind"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
if out=$(FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude Again 2>&1); then fail "the same account was added twice"; fi
[[ $out == *"That's Work (work@example.com). Try again"* ]] || fail "the refusal does not name the account: $out"
if out=$(FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add claude Again 2>&1); then fail "the primary was added as a second account"; fi
[[ $out == *"That's Main (main@example.com)"* ]] || fail "the refusal does not name Main: $out"
[[ $(registry claude '.accounts | length') == 2 ]] || fail "the registry changed"
[[ -z $(ls -A "$STATE/accounts/claude/.pending") && $(ls "$STATE/accounts/claude") == work ]] || fail "a home was left behind: $(ls -A "$STATE/accounts/claude")"
ok
cleanup_sandbox

begin "a first sign-in that wrote no credentials is not one: no default agent, no registry, no refresh"
setup
# The browser was closed: the CLI exits 0 and leaves nothing behind.
if out=$(FIX_NOLOGIN=1 "$AGENT" account add claude 2>&1); then fail "an unfinished first sign-in was accepted: $out"; fi
[[ $out == *"signing in to Claude did not finish"* && $out != *"Signed in to Claude"* ]] || fail "the first sign-in claimed to finish: $out"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "an agent nobody signed in to became the default"
[[ ! -e $STATE/accounts/claude.json ]] || fail "a registry was made for a sign-in that never happened"
[[ ! -e $SANDBOX/calls/cachyos-agent-usage-update ]] || fail "usage was collected for a sign-in that never happened"
# A login that fails outright is the same.
if out=$(FIX_LOGINFAIL=1 "$AGENT" account add claude 2>&1); then fail "a failed first login was accepted: $out"; fi
[[ $out == *"signing in to Claude did not finish"* && ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "a failed first login: $out"
ok
cleanup_sandbox

begin "--reauth reports a login that did not finish and changes nothing"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
before=$(<"$STATE/accounts/claude.json")
sleep 0.3 # the usage refreshes the sign-ins above started in the background
rm -f "$SANDBOX/calls/cachyos-agent-usage-update"
for who in primary work; do
  if out=$(FIX_LOGINFAIL=1 "$AGENT" account add --reauth "$who" claude 2>&1); then fail "--reauth $who accepted a login that failed: $out"; fi
  [[ $out == *"signing in to Claude did not finish"* && $out != *"again."* ]] || fail "--reauth $who said: $out"
done
[[ $(<"$STATE/accounts/claude.json") == "$before" ]] || fail "--reauth changed the registry"
[[ ! -e $SANDBOX/calls/cachyos-agent-usage-update ]] || fail "usage was refreshed for a sign-in that did not finish"
ok
cleanup_sandbox

begin "a login that wrote nothing adds no account"
setup
sign_in claude u-main main@example.com
if out=$(FIX_NOLOGIN=1 "$AGENT" account add claude Ghost 2>&1); then fail "an unfinished login was accepted"; fi
[[ $out == *"The login didn't finish"* ]] || fail "no explanation: $out"
[[ $("$AGENT" account list claude --json | jq '.[0].accounts | length') == 1 && -z $(ls -A "$STATE/accounts/claude/.pending") ]] || fail "state was left behind"
ok
cleanup_sandbox

begin "a Firefox-family default opens a private window, an unknown one never opens a browser"
setup
sign_in claude u-main main@example.com
stub firefox
stub xdg-settings 'echo firefox.desktop'
printf '[Desktop Entry]\nExec=firefox %%u\n' >"$XDG_DATA_HOME/applications/firefox.desktop"
sign_in claude u-work work@example.com Work
eventually called firefox "--private-window" || fail "Firefox was not given --private-window"
[[ $(<"$SANDBOX/calls/firefox") == "--private-window
https://claude.ai/oauth" ]] || fail "Firefox got the wrong arguments: $(<"$SANDBOX/calls/firefox")"
stub xdg-settings 'echo mystery.desktop'
printf '[Desktop Entry]\nExec=mystery-browser %%u\n' >"$XDG_DATA_HOME/applications/mystery.desktop"
# no controlling terminal, so the link script has nowhere to print and stays quiet
out=$(FIX_ID=u-side FIX_EMAIL=side@example.com setsid -w "$AGENT" account add claude Side 2>&1 </dev/null)
[[ $out == *"not one this command can open in a private window"* ]] || fail "the user is not told to open a private window: $out"
[[ $(registry claude '.accounts | length') == 3 ]] || fail "the account was not added"
[[ $(grep -c . "$SANDBOX/calls/brave" 2>/dev/null || echo 0) == 0 && $(grep -c -- "--private-window" "$SANDBOX/calls/firefox") == 1 ]] || fail "a browser was opened for an unknown default"
ok
cleanup_sandbox

begin "every browser family the table knows gets its own private-window flag"
setup
sign_in claude u-main main@example.com
# Command name, then the flag that family takes. A flag the browser does not know, or a browser
# missing from the table, would send the login through the window that is already signed in.
for entry in firefox:--private-window librewolf:--private-window waterfox:--private-window floorp:--private-window \
  zen-browser:--private-window microsoft-edge-stable:--inprivate chromium:--incognito google-chrome-stable:--incognito \
  brave:--incognito vivaldi-stable:--incognito opera:--incognito; do
  name=${entry%%:*}
  flag=${entry#*:}
  stub "$name"
  stub xdg-settings "echo $name.desktop"
  printf '[Desktop Entry]\nExec=%s %%u\n' "$name" >"$XDG_DATA_HOME/applications/$name.desktop"
  sign_in claude "u-$name" "$name@example.com" "$name"
  eventually called "$name" "$flag" || fail "$name was not given $flag: $(cat "$SANDBOX/calls/$name" 2>/dev/null)"
  [[ $(<"$SANDBOX/calls/$name") == "$flag
https://claude.ai/oauth" ]] || fail "$name got the wrong arguments: $(<"$SANDBOX/calls/$name")"
done
ok
cleanup_sandbox

begin "interrupting a sign-in stops the CLI and leaves no half-made account"
setup
sign_in claude u-main main@example.com
# shellcheck disable=SC2016 # a program for the stub's own bash
stub claude 'echo $$ >"$SANDBOX/cli.pid"; exec sleep 30'
FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude Work >"$SANDBOX/out" 2>&1 </dev/null &
adding=$!
eventually test -s "$SANDBOX/cli.pid" || fail "the sign-in never started"
kill -TERM "$adding"
status=0
wait "$adding" || status=$?
[[ $status == 130 ]] || fail "an interrupted add exited $status: $(<"$SANDBOX/out")"
eventually gone "$(<"$SANDBOX/cli.pid")" || fail "the CLI's login is still running"
[[ -z $(ls -A "$STATE/accounts/claude/.pending") && $("$AGENT" account list claude --json | jq '.[0].accounts | length') == 1 ]] || fail "state was left behind"
! compgen -G "$XDG_RUNTIME_DIR/cachyos-agent-browser.*" >/dev/null || fail "the browser script was left behind"
ok
cleanup_sandbox

begin "--reauth signs in again in the account's own home and never adds one"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
: >"$SANDBOX/logins"
FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add --reauth work claude >/dev/null
[[ $(<"$SANDBOX/logins") == "claude CLAUDE_CONFIG_DIR=$STATE/accounts/claude/work browser=yes" ]] || fail "work was not signed in again in its home: $(<"$SANDBOX/logins")"
: >"$SANDBOX/logins"
FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add --reauth main claude >/dev/null
FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add --reauth primary claude >/dev/null
[[ $(<"$SANDBOX/logins") == "claude CLAUDE_CONFIG_DIR=unset browser=no
claude CLAUDE_CONFIG_DIR=unset browser=no" ]] || fail "Main was not signed in again through the normal browser: $(<"$SANDBOX/logins")"
if out=$("$AGENT" account add --reauth nobody claude 2>&1); then fail "an unknown account was accepted"; fi
[[ $out == *"no Claude account named nobody"* ]] || fail "no explanation: $out"
[[ $(registry claude '.accounts | length') == 2 ]] || fail "--reauth changed the registry"
ok
cleanup_sandbox

begin "--reauth refuses a login that is not the account's own and gives its sign-in back"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
work=$STATE/accounts/claude/work
creds=$(cat "$work/.credentials.json" "$work/.claude.json")
: >"$SANDBOX/calls/cachyos-agent-usage-update"
# the private window is still signed in as Main
if out=$(FIX_ID=u-main FIX_EMAIL=main@example.com "$AGENT" account add --reauth work claude 2>&1); then fail "Main's login was accepted as Work's: $out"; fi
[[ $out == *"That's Main (main@example.com), not Work."* && $out != *"Signed in to Claude again"* ]] || fail "no refusal naming Main: $out"
[[ $creds == "$(cat "$work/.credentials.json" "$work/.claude.json")" && -L $work/settings.json ]] || fail "Work's own sign-in was not put back"
"$AGENT" account state refresh
[[ $(registry claude '[.accounts[] | .accountId] | join(",")') == u-main,u-work && $(registry claude '.accounts[1].email') == work@example.com ]] || fail "the registry holds one account twice: $(registry claude .accounts)"
# a stranger is no better than Main
if out=$(FIX_ID=u-other FIX_EMAIL=other@example.com "$AGENT" account add --reauth work claude 2>&1); then fail "a third account was accepted as Work: $out"; fi
[[ $out == *"That's other@example.com, not Work."* ]] || fail "no refusal naming the stranger: $out"
[[ $creds == "$(cat "$work/.credentials.json" "$work/.claude.json")" ]] || fail "Work's own sign-in was not put back after the stranger"
# Main cannot take Work's login either; its login lives in the CLI's own home
# and is not put back, so the refusal has to say what is there now
if out=$(FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add --reauth main claude 2>&1); then fail "Work's login was accepted as Main's: $out"; fi
[[ $out == *"That's Work (work@example.com), not Main."* ]] || fail "no refusal naming Work: $out"
sleep 0.3
[[ ! -s $SANDBOX/calls/cachyos-agent-usage-update ]] || fail "the usage records were refreshed for a refused sign-in: $(<"$SANDBOX/calls/cachyos-agent-usage-update")"
[[ -z $(ls -A "$XDG_RUNTIME_DIR") ]] || fail "a snapshot or script was left behind: $(ls -A "$XDG_RUNTIME_DIR")"
ok
cleanup_sandbox

begin "a completed sign-in that was interrupted is registered instead of asking again"
setup
sign_in claude u-main main@example.com
pending=$("$AGENT" account state begin claude Recovered 0)
CLAUDE_CONFIG_DIR=$pending FIX_ID=u-rec FIX_EMAIL=rec@example.com claude auth login >/dev/null
: >"$SANDBOX/logins"
out=$("$AGENT" account add claude)
[[ $out == *"Added Recovered (rec@example.com)."* ]] || fail "the interrupted login was not recovered: $out"
[[ ! -s $SANDBOX/logins ]] || fail "the CLI asked for another login"
[[ $(registry claude '.accounts[1] | .id + "," + .home') == "recovered,$STATE/accounts/claude/recovered" && ! -e $pending ]] || fail "recovered entry: $(registry claude '.accounts[1]')"
ok
cleanup_sandbox

begin "add reads its options wherever they stand, and keeps a dash-leading label behind --"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
: >"$SANDBOX/logins"
ADD=$REPO_ROOT/bin/cachyos-agent-account-add
# Help after the provider is help, not a label that starts a real sign-in.
out=$("$ADD" claude --help 2>&1) || true
[[ $out == "Usage: cachyos-agent account add"* ]] || fail "claude --help did not print usage: $out"
if out=$("$ADD" claude --bogus 2>&1); then fail "an unknown option after the provider was accepted"; fi
[[ $out == "Usage: cachyos-agent account add"* ]] || fail "--bogus after the provider did not print usage: $out"
[[ ! -s $SANDBOX/logins ]] || fail "a sign-in started for an option: $(<"$SANDBOX/logins")"
[[ $(registry claude '.accounts | length') == 2 ]] || fail "an option became an account: $(registry claude '[.accounts[].label]')"
# --reauth after the provider is the same request as before it.
FIX_ID=u-work FIX_EMAIL=work@example.com "$ADD" claude --reauth work >/dev/null 2>&1 || true
[[ $(<"$SANDBOX/logins") == "claude CLAUDE_CONFIG_DIR=$STATE/accounts/claude/work browser=yes" ]] || fail "--reauth after the provider did not sign work in again: $(<"$SANDBOX/logins")"
[[ $(registry claude '.accounts | length') == 2 ]] || fail "--reauth after the provider added an account"
# A label that has to start with a dash goes after --.
FIX_ID=u-odd FIX_EMAIL=odd@example.com "$ADD" claude -- --odd >/dev/null 2>&1 || true
[[ $(registry claude '.accounts[2] | .id + "/" + .label') == "odd/--odd" ]] || fail "the label after -- was not kept: $(registry claude '.accounts[2]')"
ok
cleanup_sandbox

begin "add and exec run the CLI from ~/.local/bin when PATH does not reach it, as launch does"
setup
sign_in claude u-main main@example.com
# Only ~/.local/bin has claude, as in a desktop session that lacks that directory on PATH.
mkdir -p "$HOME/.local/bin" "$SANDBOX/system"
printf '#!/bin/bash\n%s\n' "$CLAUDE_STUB" >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
rm "$SANDBOX/stubs/claude"
ln -s /usr/bin/* "$SANDBOX/system/"
rm -f "$SANDBOX/system/claude"
PATH=$SANDBOX/stubs:$SANDBOX/system
: >"$SANDBOX/logins"
out=$(FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude Work 2>&1) || fail "add did not find ~/.local/bin/claude: $out"
[[ $out == *"Added Work"* && $(registry claude '.accounts | length') == 2 ]] || fail "no account was added: $out"
out=$("$AGENT" account exec claude --continue) || fail "exec did not find ~/.local/bin/claude"
[[ $out == *"args=--continue" ]] || fail "exec did not run it: $out"
PATH=$BASE_PATH
ok
cleanup_sandbox

begin "a label that is two provider names is a label"
setup
stub cachyos-agent-default 'echo claude'
sign_in claude u-main main@example.com
FIX_ID=u-two FIX_EMAIL=two@example.com "$AGENT" account add "codex grok" >/dev/null || fail "a label made of provider names was refused"
[[ $(registry claude '.accounts[1] | .id + "/" + .label') == "codex-grok/codex grok" ]] || fail "the label was not kept: $(registry claude '.accounts')"
ok
cleanup_sandbox

begin "a very long label still registers, under a shortened id"
setup
sign_in claude u-main main@example.com
label=$(printf 'a%.0s' {1..300})
out=$(FIX_ID=u-long FIX_EMAIL=long@example.com "$AGENT" account add claude "$label" 2>&1) || fail "a 300 character label did not register: $out"
[[ $(registry claude '.accounts | length') == 2 && $(registry claude '.accounts[1].id | length') -le 40 ]] || fail "the id is not short: $(registry claude '.accounts[1].id')"
[[ -z $(ls -A "$STATE/accounts/claude/.pending" 2>/dev/null) ]] || fail "the login was left pending: $(ls -A "$STATE/accounts/claude/.pending")"
ok
cleanup_sandbox

begin "add explains how to install a missing CLI, and checks the provider first"
setup
mkdir "$SANDBOX/tools"
for tool in dirname readlink; do ln -s "$(type -P "$tool")" "$SANDBOX/tools/$tool"; done
if out=$(PATH=$SANDBOX/tools "$REPO_ROOT/bin/cachyos-agent-account-add" codex 2>&1); then fail "add ran without the CLI"; fi
[[ $out == *"Codex's CLI (codex) is not installed. Install it with: cachyos-agent install codex"* ]] || fail "no install hint: $out"
if "$AGENT" account add bogus >/dev/null 2>&1; then fail "an unknown provider was accepted"; fi
[[ ! -e $STATE/accounts ]] || fail "state was created for a failed add"
ok
cleanup_sandbox

# ---- use, home -----------------------------------------------------------------

begin "add asks for a label at a terminal and uses the answer"
setup
# script(1) gives the command a terminal on stdin and passes what it is given to it.
if ! script -qec 'test -t 0' /dev/null </dev/null >/dev/null 2>&1; then
  printf 'UNVERIFIED add asks for a label: script cannot provide a terminal here\n'
else
  sign_in claude u-main main@example.com
  cmd=$(printf '%q ' env FIX_ID=u-work FIX_EMAIL=work@example.com "$AGENT" account add claude)
  out=$(printf 'Prompted\n' | SHELL=/bin/bash script -qec "$cmd" /dev/null) || fail "add at a terminal failed: $out"
  [[ $out == *"Name this Claude account (empty to use its email): "* ]] || fail "no prompt for a label: $out"
  [[ $(registry claude '.accounts[1].label') == Prompted ]] || fail "the label typed at the prompt was not used: $(registry claude '.accounts[1].label')"
  # An empty answer takes the email's name, as the prompt says.
  cmd=$(printf '%q ' env FIX_ID=u-home FIX_EMAIL=home@example.com "$AGENT" account add claude)
  printf '\n' | SHELL=/bin/bash script -qec "$cmd" /dev/null >/dev/null || fail "add with an empty answer failed"
  [[ $(registry claude '.accounts[2].label') == home ]] || fail "an empty answer did not take the email's name: $(registry claude '.accounts[2].label')"
fi
ok
cleanup_sandbox

begin "use and add print no control characters from an account's label, email or plan"
setup
stub notify-send
export DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null
sign_in claude u-main main@example.com
# What the CLI wrote is vendor text; JSON carries the escape as \u001b, and an unnamed account is
# labelled by the start of its email.
add_out=$(FIX_TIER=none FIX_SUB='pro\u001b[2Jx' FIX_ID=u-evil FIX_EMAIL='evil\u001b[31m@example.com' "$AGENT" account add claude)
[[ $add_out != *$'\033'* ]] || fail "add printed an escape sequence: $(printf '%q' "$add_out")"
[[ $add_out == *"Added evil[31m (evil[31m@example.com)."* ]] || fail "add said: $(printf '%q' "$add_out")"
id=$(registry claude '.accounts[1].id')
use_out=$("$AGENT" account use claude "$id")
[[ $use_out != *$'\033'* ]] || fail "use printed an escape sequence: $(printf '%q' "$use_out")"
[[ $use_out == "New Claude sessions now use evil[31m (Pro[2Jx). Running sessions stay on "* ]] || fail "use said: $(printf '%q' "$use_out")"
back_out=$("$AGENT" account use claude main)
[[ $back_out == *"Running sessions stay on evil[31m."* && $back_out != *$'\033'* ]] || fail "the account left was named: $(printf '%q' "$back_out")"
! grep -q $'\033' "$SANDBOX/calls/notify-send" || fail "the notification carried an escape sequence"
rm_out=$("$AGENT" account remove claude "$id" </dev/null)
[[ $rm_out != *$'\033'* ]] || fail "remove printed an escape sequence: $(printf '%q' "$rm_out")"
ok
cleanup_sandbox

begin "a refusal names the account without the control characters of its email"
setup
sign_in claude u-main main@example.com
# The vendor's profile holds the escape; the registry keeps it, and so does a label made from it.
sign_in claude u-evil 'evil\u001b[2Jme@example.test'
bad='evil\u001b[2Jme@example.test'
if out=$(FIX_ID=u-evil FIX_EMAIL=$bad "$AGENT" account add claude Again 2>&1); then fail "the same account was added twice"; fi
[[ $out == *"That's evil[2Jme (evil[2Jme@example.test). Try again"* && $out != *$'\033'* ]] || fail "add's refusal said: $(printf '%q' "$out")"
if out=$(FIX_ID=u-evil FIX_EMAIL=$bad "$AGENT" account add --reauth main claude 2>&1); then fail "another account's login was accepted as Main's"; fi
[[ $out == *"That's evil[2Jme (evil[2Jme@example.test), not Main."* && $out != *$'\033'* ]] || fail "the label in --reauth's refusal said: $(printf '%q' "$out")"
if out=$(FIX_ID=u-other FIX_EMAIL=$bad "$AGENT" account add --reauth evil-2jme claude 2>&1); then fail "a stranger was accepted as the account"; fi
[[ $out == *"That's evil[2Jme@example.test, not evil[2Jme."* && $out != *$'\033'* ]] || fail "the email in --reauth's refusal said: $(printf '%q' "$out")"
ok
cleanup_sandbox

begin "use switches the account new sessions start as and home prints its path, nothing for Main"
setup
[[ -z $("$AGENT" account home claude) && $? == 0 ]] || fail "home printed something before any account exists"
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
stub notify-send
export DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null
[[ -z $("$AGENT" account home claude) ]] || fail "home printed a path while Main is active"
out=$("$AGENT" account use claude work)
[[ $out == "New Claude sessions now use Work (Max 5x). Running sessions stay on Main.
They follow it when started with cachyos-agent launch or cachyos-agent account exec claude; a plain claude command still uses the login in ~/.claude." ]] || fail "use said: $out"
[[ $("$AGENT" account home claude) == "$STATE/accounts/claude/work" ]] || fail "home is not the work home: $("$AGENT" account home claude)"
[[ $(registry claude .active) == work ]] || fail "the registry does not record the switch"
called notify-send "New Claude sessions use Work" || fail "no notification for a use that was not run in a terminal"
eventually called cachyos-agent-usage-update "--limits-only" || fail "the usage record was not refreshed"
[[ $("$AGENT" account use claude work) == "New Claude sessions already use Work (Max 5x)." ]] || fail "using the active account again said the wrong thing"
[[ $("$AGENT" account use claude main) == "New Claude sessions now use Main (Max 5x). Running sessions stay on Work." ]] || fail "switching back to Main said something about plain claude"
[[ -z $("$AGENT" account home claude) ]] || fail "home printed a path after switching back to Main"
"$AGENT" account use claude next >/dev/null
[[ $(registry claude .active) == work ]] || fail "next did not move on to work"
"$AGENT" account use claude next >/dev/null
[[ $(registry claude .active) == main ]] || fail "next did not wrap around to main"
"$AGENT" account use claude work >/dev/null
"$AGENT" account use claude primary >/dev/null
[[ $(registry claude .active) == main ]] || fail "'primary' did not select the first login"
if out=$("$AGENT" account use claude nobody 2>&1); then fail "an unknown account was accepted"; fi
[[ $out == *"No Claude account named nobody"* ]] || fail "no explanation: $out"
if "$AGENT" account use claude work extra >/dev/null 2>&1; then fail "an extra argument was accepted"; fi
ok
cleanup_sandbox

begin "a running session's pin beats the registry in home"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
"$AGENT" account use claude work >/dev/null 2>&1
[[ -z $(CACHYOS_AGENT_CLAUDE_HOME='' "$AGENT" account home claude) ]] || fail "an empty pin (Main) did not win"
[[ $(CACHYOS_AGENT_CLAUDE_HOME=/pinned "$AGENT" account home claude) == /pinned ]] || fail "a pin did not win"
if "$AGENT" account home bogus >/dev/null 2>&1; then fail "home accepted an unknown provider"; fi
ok
cleanup_sandbox

# ---- list --------------------------------------------------------------------

begin "list shows signed-in accounts with their latest limits and --json parses"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
sign_in grok u-grok grok@example.com
mkdir -p "$STATE/usage"
echo '{"accounts":[{"id":"main","limits":[{"label":"5h","percent":0.42}]},{"id":"work","limits":[{"label":"7d","percent":0.9},{"label":"5h"}]}]}' >"$STATE/usage/claude.json"
echo '{"limits":[{"label":"week","percent":0.1}]}' >"$STATE/usage/grok.json"
echo '{not json' >"$STATE/usage/codex.json"
out=$("$AGENT" account list)
[[ $out == "Claude: notify mode at 95%"* ]] || fail "no provider header: $out"
grep -qE '^ +\* +main +Main +Max 5x +main@example.com +5h: 42%$' <<<"$out" || fail "Main's line is wrong: $out"
grep -qE '^ +work +Work +Max 5x +work@example.com +7d: 90%$' <<<"$out" || fail "Work's line is wrong: $out"
grep -qE '^Grok: notify mode at 95%$' <<<"$out" || fail "no Grok header: $out"
grep -qE 'week: 10%$' <<<"$out" || fail "the single-account record's limits are missing: $out"
[[ $out != *Codex* ]] || fail "a provider nobody signed in to was listed"
[[ $out != *SECRET* ]] || fail "a token reached the listing"
json=$("$AGENT" account list --json)
jq -e 'map(.provider) == ["claude","codex","grok"] and .[0].accounts[0].limits[0].percent == 0.42 and .[0].accounts[1].limits[1].label == "5h"
       and .[1].accounts[0].signedIn == false and .[2].accounts[0].limits[0].percent == 0.1' <<<"$json" >/dev/null || fail "unexpected --json: $json"
[[ $json != *SECRET* ]] || fail "a token reached the JSON"
jq -e 'length == 1 and .[0].name == "Claude" and (.[0].accounts | length) == 2' <<<"$("$AGENT" account list claude --json)" >/dev/null || fail "list <provider> did not narrow to the provider"
ok
cleanup_sandbox

begin "list prints no control character from a record or an account"
setup
sign_in claude u-main main@example.com
mkdir -p "$STATE/usage"
# A vendor's response names a model, and the name is shown as the limit's label.
jq -n '{limits: [{label: "Opus\u001b]0;pwned-title\u0007\u001b[2J Weekly", percent: 0.5}, {label: "Tab\there\u009b", percent: 0.1}]}' >"$STATE/usage/claude.json"
out=$("$AGENT" account list claude)
leftover=$(printf '%s' "$out" | tr -d '\n' | LC_ALL=C tr -d '[:print:]')
[[ -z $leftover ]] || fail "the listing holds control characters: $(printf '%s' "$out" | cat -v)"
[[ $out == *"Opus]0;pwned-title[2J Weekly: 50%"* && $out == *"Tabhere: 10%"* ]] || fail "the printable text was changed: $out"
[[ $("$AGENT" account list claude --json) == *'pwned-title'* ]] || fail "--json should keep the record as it is"
ok
cleanup_sandbox

begin "list names a limit by its title, as the usage report does, so a model's window is not the account's"
setup
sign_in claude u-main main@example.com
mkdir -p "$STATE/usage"
# Codex's per-model buckets carry the generic label and put the model only in the title.
jq -n '{limits: [{label: "5h window", percent: 0.4}, {label: "Weekly (7-day)", percent: 0.2},
  {label: "5h window", title: "GPT-5.3-Codex-Spark Session", percent: 0.05},
  {label: "Weekly (7-day)", title: "GPT-5.3-Codex-Spark Weekly\u001b[2J", percent: 0.01},
  {label: "Opus", title: "", percent: 0.1}]}' >"$STATE/usage/claude.json"
out=$("$AGENT" account list claude)
[[ $out == *"5h window: 40%, Weekly (7-day): 20%, GPT-5.3-Codex-Spark Session: 5%, GPT-5.3-Codex-Spark Weekly[2J: 1%, Opus: 10%"* ]] \
  || fail "the limits are not named by title where there is one: $out"
leftover=$(printf '%s' "$out" | tr -d '\n' | LC_ALL=C tr -d '[:print:]')
[[ -z $leftover ]] || fail "a title brought a control character into the listing: $(printf '%s' "$out" | cat -v)"
ok
cleanup_sandbox

begin "the registry keeps Omarchy's schema, which the usage collectors read"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
jq -e 'keys == ["accounts","active","alert","switch","threshold"]
       and all(.accounts[]; keys == ["accountId","email","home","id","label","org","plan","primary"])' "$STATE/accounts/claude.json" >/dev/null \
  || fail "unexpected registry: $(<"$STATE/accounts/claude.json")"
sign_in codex u-cx cx@example.com
sign_in codex u-cx2 cx2@example.com Second
[[ $(registry codex '.accounts[1] | [.plan, .email] | join(",")') == "Plus,cx2@example.com" ]] || fail "codex identity: $(registry codex '.accounts[1]')"
ok
cleanup_sandbox

# ---- rename, remove ------------------------------------------------------------

begin "rename changes the label and the id but leaves the home where sessions are using it"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
"$AGENT" account use claude work >/dev/null 2>&1
out=$("$AGENT" account rename claude work Work Laptop)
[[ $out == "Renamed to Work Laptop. Switch to it with: cachyos-agent account use claude work-laptop" ]] || fail "rename said: $out"
[[ $(registry claude '.accounts[1] | [.id, .label, .home] | join(",")') == "work-laptop,Work Laptop,$STATE/accounts/claude/work" && -d $STATE/accounts/claude/work ]] \
  || fail "rename moved or mislabelled the account: $(registry claude '.accounts[1]')"
[[ $(registry claude .active) == work-laptop && $("$AGENT" account home claude) == "$STATE/accounts/claude/work" ]] || fail "the active account lost its selection"
"$AGENT" account rename claude primary Home >/dev/null 2>&1
[[ $(registry claude '.accounts[0] | [.id, .label, .primary] | join(",")') == "home,Home,true" ]] || fail "the primary was not renamed"
"$AGENT" account use claude primary >/dev/null 2>&1
[[ $(registry claude .active) == home ]] || fail "'primary' no longer selects the first login after a rename"
"$AGENT" account rename claude home Next >/dev/null 2>&1
[[ $(registry claude '.accounts[0].id') == next-2 ]] || fail "a reserved word became an id: $(registry claude '.accounts[0].id')"
"$AGENT" account rename claude work-laptop Next >/dev/null 2>&1
[[ $(registry claude '.accounts[1].id') == next-3 ]] || fail "a taken id was reused: $(registry claude '.accounts[1].id')"
if "$AGENT" account rename claude work-laptop >/dev/null 2>&1; then fail "rename without a name was accepted"; fi
if "$AGENT" account rename claude nobody Name >/dev/null 2>&1; then fail "an unknown account was renamed"; fi
ok
cleanup_sandbox

begin "remove deletes only the account's home, never the primary or one a session is using"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
home=$STATE/accounts/claude/work
mkdir -p "$HOME/.claude/projects" && echo keep >"$HOME/.claude/projects/keep.txt"
if out=$("$AGENT" account remove claude main 2>&1 </dev/null); then fail "the primary account was removed"; fi
[[ $out == *"can't be removed here"* ]] || fail "no explanation: $out"
env CLAUDE_CONFIG_DIR="$home" sleep 30 &
session=$!
if out=$("$AGENT" account remove claude work 2>&1 </dev/null); then fail "an account in use was removed"; fi
[[ $out == *"A running Claude session uses Work"* && -d $home ]] || fail "no refusal for a running session: $out"
kill "$session"
wait "$session" 2>/dev/null || true
"$AGENT" account use claude work >/dev/null 2>&1
out=$("$AGENT" account remove claude work </dev/null)
[[ $out == "Forgot Work." ]] || fail "remove said: $out"
[[ ! -e $home && -f $HOME/.claude/projects/keep.txt && -f $HOME/.claude/.credentials.json ]] || fail "remove deleted the wrong files"
[[ $(registry claude '[.accounts[].id] | join(",")') == main && $(registry claude .active) == main ]] || fail "registry after remove: $(<"$STATE/accounts/claude.json")"
eventually called cachyos-agent-usage-update "--limits-only" || fail "the usage record was not refreshed"
if "$AGENT" account remove claude work >/dev/null 2>&1 </dev/null; then fail "an account was removed twice"; fi
ok
cleanup_sandbox

begin "remove never deletes a home outside accounts/<provider>/, whatever the registry says"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
mkdir -p "$HOME/.claude/projects" "$SANDBOX/precious"
echo keep >"$HOME/.claude/projects/keep.txt"
echo keep >"$SANDBOX/precious/notes.txt"
# A registry entry whose home is the primary's own, one with no home (which falls back to
# the primary's), and one pointing at a directory that is not an account's at all: the
# registry is a file on disk and may say anything, and only a home the commands made
# under accounts/claude/ is theirs to delete.
jq --arg claude "$HOME/.claude" --arg precious "$SANDBOX/precious" '.accounts += [
    {id: "aliased", label: "Aliased", home: $claude, primary: false},
    {id: "blank", label: "Blank", home: "", primary: false},
    {id: "elsewhere", label: "Elsewhere", home: $precious, primary: false}]' "$STATE/accounts/claude.json" >"$SANDBOX/registry.json"
cp "$SANDBOX/registry.json" "$STATE/accounts/claude.json"
for id in aliased blank elsewhere; do
  out=$("$AGENT" account remove claude "$id" </dev/null 2>&1) || fail "removing $id failed: $out"
  [[ $out == "Forgot "* ]] || fail "remove said: $out"
done
[[ -f $HOME/.claude/projects/keep.txt && -f $HOME/.claude/.credentials.json && -f $HOME/.claude.json ]] || fail "remove deleted the primary's files"
[[ -f $SANDBOX/precious/notes.txt ]] || fail "remove deleted a directory outside accounts/claude/"
[[ $(registry claude '[.accounts[].id] | join(",")') == main,work ]] || fail "the entries were not dropped: $(registry claude '[.accounts[].id]')"
[[ -d $STATE/accounts/claude/work ]] || fail "remove deleted an account it was not asked about"
ok
cleanup_sandbox

begin "remove asks first in a terminal and keeps the account unless told yes"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
answer() { printf '%s\n' "$1" | script -qefc "$(printf '%q ' "$AGENT" account remove claude work)" /dev/null; }
if out=$(answer n); then fail "declining the prompt succeeded"; fi
[[ $out == *"Forget the claude account work?"* && -d $STATE/accounts/claude/work ]] || fail "the prompt did not protect the account: $out"
answer y >/dev/null || fail "confirming the prompt failed"
[[ ! -e $STATE/accounts/claude/work ]] || fail "the account survived a yes"
ok
cleanup_sandbox

# ---- exec ----------------------------------------------------------------------

begin "exec runs the provider CLI as the selected account and pins it for children"
setup
declare -A home_env=([claude]=CLAUDE_CONFIG_DIR [codex]=CODEX_HOME [grok]=GROK_HOME)
for provider in claude codex grok; do
  pin=CACHYOS_AGENT_${provider^^}_HOME env_var=${home_env[$provider]}
  sign_in "$provider" "u-$provider" "$provider@example.com"
  sign_in "$provider" "u-$provider-2" "$provider-2@example.com" Work
  home=$STATE/accounts/$provider/work
  out=$("$AGENT" account exec "$provider" --continue 'a b')
  [[ $out == "$env_var=unset
$pin=
args=--continue a b" ]] || fail "$provider on Main: $out"
  "$AGENT" account use "$provider" work >/dev/null 2>&1
  out=$("$AGENT" account exec "$provider" --continue 'a b')
  [[ $out == "$env_var=$home
$pin=$home
args=--continue a b" ]] || fail "$provider on Work: $out"
  out=$(env "$env_var=/explicit" "$AGENT" account exec "$provider")
  [[ $out == "$env_var=/explicit
$pin=unset
args=" ]] || fail "$provider with an explicit home: $out"
  out=$(env "$pin=" "$AGENT" account exec "$provider")
  [[ $out == "$env_var=unset
$pin=
args=" ]] || fail "$provider in a session pinned to Main: $out"
done
if "$AGENT" account exec bogus >/dev/null 2>&1; then fail "exec accepted an unknown provider"; fi
mkdir "$SANDBOX/tools"
for tool in dirname readlink; do ln -s "$(type -P "$tool")" "$SANDBOX/tools/$tool"; done
if out=$(PATH=$SANDBOX/tools "$REPO_ROOT/bin/cachyos-agent-account-exec" claude 2>&1); then fail "exec ran without the CLI"; fi
[[ $out == *"Claude's CLI (claude) is not installed. Install it with: cachyos-agent install claude"* ]] || fail "no install hint: $out"
ok
cleanup_sandbox

# ---- mode ----------------------------------------------------------------------

begin "mode stores the switching mode and threshold and describes them"
setup
sign_in claude u-main main@example.com
[[ $("$AGENT" account mode claude) == "Claude notifies at 95% and switches when you say so." ]] || fail "default mode: $("$AGENT" account mode claude)"
[[ $("$AGENT" account mode claude auto 90) == "Claude switches new sessions to the account with the most headroom at 90%." ]] || fail "auto 90"
[[ $(registry claude '[.switch, .threshold] | join(",")') == auto,90 ]] || fail "registry: $(<"$STATE/accounts/claude.json")"
[[ $("$AGENT" account list claude) == "Claude: auto mode at 90%"* ]] || fail "list header for auto: $("$AGENT" account list claude)"
[[ $("$AGENT" account mode claude notify) == "Claude notifies at 90% and switches when you say so." && $(registry claude .switch) == manual ]] || fail "notify is not stored as manual"
"$AGENT" account mode claude auto >/dev/null
[[ $(registry claude '[.switch, .threshold] | join(",")') == auto,90 ]] || fail "a mode without a threshold changed the threshold"
"$AGENT" account mode claude manual 10 >/dev/null
[[ $(registry claude '[.switch, .threshold] | join(",")') == manual,50 ]] || fail "the threshold was not clamped up to 50"
"$AGENT" account mode claude auto 500 >/dev/null
[[ $(registry claude .threshold) == 100 ]] || fail "the threshold was not clamped down to 100"
if out=$("$AGENT" account mode claude auto abc 2>&1); then fail "a non-numeric threshold was accepted"; fi
[[ $out == *"percentage between 50 and 100"* && $(registry claude .threshold) == 100 ]] || fail "bad threshold: $out"
if out=$("$AGENT" account mode claude sometimes 2>&1); then fail "an unknown mode was accepted"; fi
[[ $out == *"notify or auto"* ]] || fail "bad mode: $out"
ok
cleanup_sandbox

# ---- autoswitch ----------------------------------------------------------------

# usage_record <main fraction> <work fraction>: the usage record the collectors
# would have written for two Claude accounts, with windows that reset far ahead.
usage_record() {
  mkdir -p "$STATE/usage"
  jq -n --argjson m "$1" --argjson w "$2" '{accounts: [
    {id: "main", limits: [{label: "5h", percent: $m, resetsAt: "2999-01-01T00:00:00Z"}]},
    {id: "work", limits: [{label: "5h", percent: $w, resetsAt: "2999-01-01T00:00:00Z"}]}]}' >"$STATE/usage/claude.json"
}

# active_is <id>: whether the Claude registry's active account is that one.
active_is() {
  [[ $(registry claude .active) == "$1" ]]
}

# two_accounts: Main and Work signed in, with desktop notifications stubbed.
two_accounts() {
  setup
  sign_in claude u-main main@example.com
  sign_in claude u-work work@example.com Work
  stub notify-send
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null
}

begin "autoswitch in auto mode moves new sessions to the account with room and says so"
two_accounts
"$AGENT" account mode claude auto 90 >/dev/null
usage_record 0.5 0.1
[[ -z $("$AGENT" account state autoswitch claude) && $(registry claude .active) == main ]] || fail "switched below the threshold"
usage_record 0.97 0.1
[[ $("$AGENT" account state autoswitch claude) == claude ]] || fail "autoswitch did not report the provider it switched"
[[ $(registry claude .active) == work && $("$AGENT" account home claude) == "$STATE/accounts/claude/work" ]] || fail "the active account did not change"
called notify-send "Main is at 97% of a Claude limit" || fail "no headline: $(<"$SANDBOX/calls/notify-send")"
called notify-send "New Claude sessions now use Work (10%)." || fail "no word on the new account: $(<"$SANDBOX/calls/notify-send")"
[[ -z $("$AGENT" account state autoswitch claude) && $(registry claude .active) == work ]] || fail "autoswitch flapped back"
ok
cleanup_sandbox

begin "autoswitch in notify mode offers a switch that a click carries out"
two_accounts
usage_record 0.97 0.1
stub notify-send 'case "$*" in *--action*) echo switch ;; esac'
[[ -z $("$AGENT" account state autoswitch claude) ]] || fail "notify mode switched by itself"
eventually active_is work || fail "clicking the notification did not switch"
called notify-send "--action=switch=Switch" || fail "no switch action: $(<"$SANDBOX/calls/notify-send")"
called notify-send "Work is at 10%. Click to switch" || fail "no offer: $(<"$SANDBOX/calls/notify-send")"
ok
cleanup_sandbox

# in_a_unit: act as the usage-update service does. systemd marks every process
# of a unit with INVOCATION_ID, and kills whatever is left in the unit's cgroup
# when its main process ends, so an offer must be started outside the unit.
in_a_unit() {
  export INVOCATION_ID=0123456789abcdef0123456789abcdef
}

begin "inside a systemd unit the notify-mode offer starts in a unit of its own"
two_accounts
in_a_unit
usage_record 0.97 0.1
stub systemd-run
[[ -z $("$AGENT" account state autoswitch claude) ]] || fail "notify mode switched by itself"
called systemd-run "--user" || fail "the offer was not started in the user manager: $(<"$SANDBOX/calls/systemd-run")"
called systemd-run "--collect" || fail "the offer's unit is not cleaned up when it ends"
called systemd-run "--property=KillMode=process" || fail "the usage refresh a click starts would die with the waiter"
called systemd-run "--setenv=CACHYOS_AGENT_STATE_DIR" || fail "the offer's unit would not find the registry"
called systemd-run "Work is at 10%. Click to switch" || fail "the unit does not run the offer: $(<"$SANDBOX/calls/systemd-run")"
sleep 0.3
[[ ! -e $SANDBOX/calls/notify-send ]] || fail "the offer also ran as a child of the unit, where systemd kills it"
ok
cleanup_sandbox

begin "the offer started in its own unit carries out a click"
two_accounts
in_a_unit
usage_record 0.97 0.1
# what systemd-run does: run the words after -- somewhere else and return
# shellcheck disable=SC2016 # a program for the stub's own bash
stub systemd-run 'while [[ $1 != -- ]]; do shift; done; shift; "$@" >/dev/null 2>&1 </dev/null &'
stub notify-send 'case "$*" in *--action*) echo switch ;; esac'
[[ -z $("$AGENT" account state autoswitch claude) ]] || fail "notify mode switched by itself"
eventually active_is work || fail "clicking the notification did not switch"
ok
cleanup_sandbox

begin "the offer started in its own unit finds the registry in a state directory only this shell names"
two_accounts
in_a_unit
# The state lives under an XDG_STATE_HOME the user manager has never heard of.
mv "$XDG_STATE_HOME" "$SANDBOX/custom-state"
export XDG_STATE_HOME=$SANDBOX/custom-state
STATE=$XDG_STATE_HOME/cachyos-agent
usage_record 0.97 0.1
# systemd-run starts the command in the user manager's environment plus what --setenv copies.
# shellcheck disable=SC2016 # a program for the stub's own bash
stub systemd-run 'unit_env=()
while [[ $1 != -- ]]; do
  case $1 in --setenv=*) name=${1#--setenv=}; unit_env+=("$name=${!name}") ;; esac
  shift
done
shift
env -i HOME="$HOME" "${unit_env[@]}" "$@" >/dev/null 2>&1 </dev/null &'
stub notify-send 'case "$*" in *--action*) echo switch ;; esac'
[[ -z $("$AGENT" account state autoswitch claude) ]] || fail "notify mode switched by itself"
eventually active_is work || fail "the click switched another registry: the real one still says $(registry claude .active), $(ls -A "$HOME/.local/state/cachyos-agent" 2>/dev/null)"
ok
cleanup_sandbox

begin "when no unit can be started the offer says how to switch"
two_accounts
in_a_unit
usage_record 0.97 0.1
stub systemd-run 'exit 1'
err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
[[ $err == "Main is at 97% of a Claude limit: Work is at 10%. Switch new sessions to it with: cachyos-agent account use claude work" ]] || fail "stderr said: $err"
sleep 0.3
[[ ! -e $SANDBOX/calls/notify-send ]] || fail "a notification was sent that nothing waits on"
ok
cleanup_sandbox

begin "a notification that is closed without a click changes nothing"
two_accounts
usage_record 0.97 0.1
"$AGENT" account state autoswitch claude >/dev/null
eventually called notify-send "--action=switch=Switch" || fail "the offer was not sent"
sleep 0.5
[[ $(registry claude .active) == main ]] || fail "the account changed without a click"
ok
cleanup_sandbox

begin "when every account is over the threshold it is said once and nothing switches"
two_accounts
"$AGENT" account mode claude auto 90 >/dev/null
usage_record 0.97 0.99
[[ -z $("$AGENT" account state autoswitch claude) && -z $("$AGENT" account state autoswitch claude) ]] || fail "autoswitch reported a switch"
[[ $(grep -c "All Claude accounts are over 90%" "$SANDBOX/calls/notify-send") == 1 ]] || fail "not said exactly once: $(<"$SANDBOX/calls/notify-send")"
called notify-send "Staying on Main. " || fail "no word on staying: $(<"$SANDBOX/calls/notify-send")"
called notify-send " resets in " || fail "no word on when an account frees up: $(<"$SANDBOX/calls/notify-send")"
[[ $(registry claude .active) == main ]] || fail "the account changed"
ok
cleanup_sandbox

begin "without a desktop the notification goes to stderr"
two_accounts
unset DBUS_SESSION_BUS_ADDRESS
"$AGENT" account mode claude auto 90 >/dev/null
usage_record 0.97 0.1
err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
[[ $err == "Main is at 97% of a Claude limit: New Claude sessions now use Work (10%)."* && ! -e $SANDBOX/calls/notify-send ]] || fail "stderr said: $err"
ok
cleanup_sandbox

begin "a notification service that is not up yet still gets the message to stderr"
two_accounts
stub notify-send 'exit 1'
"$AGENT" account mode claude auto 90 >/dev/null
usage_record 0.97 0.1
err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
called notify-send "Main is at 97% of a Claude limit" || fail "notify-send was not tried"
[[ $err == "Main is at 97% of a Claude limit: New Claude sessions now use Work (10%)."* ]] || fail "stderr said: $err"
ok
cleanup_sandbox

# alert_of: what the Claude registry remembers having said, "" for nothing.
alert_of() {
  registry claude '.alert // ""'
}

# no_alert: whether the Claude registry remembers nothing, for eventually to retry.
no_alert() {
  [[ -z $(alert_of) ]]
}

begin "a message the notification service did not take is said again at the next refresh"
two_accounts
"$AGENT" account mode claude auto 90 >/dev/null
usage_record 0.97 0.99
# The timer fires at login, before plasmashell owns the notification service.
stub notify-send 'exit 1'
"$AGENT" account state autoswitch claude >/dev/null 2>&1
[[ -z $(alert_of) ]] || fail "an alert was kept for a message nobody saw: $(alert_of)"
rm -f "$SANDBOX/calls/notify-send"
stub notify-send
"$AGENT" account state autoswitch claude >/dev/null 2>&1
called notify-send "All Claude accounts are over 90%" || fail "the message was not said again once the service was up"
[[ $(alert_of) == exhausted:main ]] || fail "the alert was not kept once the message was delivered: $(alert_of)"
rm -f "$SANDBOX/calls/notify-send"
"$AGENT" account state autoswitch claude >/dev/null 2>&1
[[ ! -e $SANDBOX/calls/notify-send ]] || fail "a delivered message was said a third time"
ok
cleanup_sandbox

begin "an offer the notification service did not show is made again at the next refresh"
two_accounts
usage_record 0.97 0.1
stub notify-send 'exit 1'
"$AGENT" account state autoswitch claude >/dev/null 2>&1
eventually called notify-send "--action=switch=Switch" || fail "the offer was not tried"
eventually no_alert || fail "an alert was kept for an offer nobody saw: $(alert_of)"
stub notify-send 'case "$*" in *--action*) echo switch ;; esac'
"$AGENT" account state autoswitch claude >/dev/null 2>&1
eventually active_is work || fail "the second offer was not made or not carried out"
ok
cleanup_sandbox

begin "an offer that could not be started is made again at the next refresh"
two_accounts
in_a_unit
usage_record 0.97 0.1
stub systemd-run 'exit 1'
"$AGENT" account state autoswitch claude >/dev/null 2>&1
[[ -z $(alert_of) ]] || fail "an alert was kept for an offer that was never made: $(alert_of)"
# shellcheck disable=SC2016 # a program for the stub's own bash
stub systemd-run 'while [[ $1 != -- ]]; do shift; done; shift; "$@" >/dev/null 2>&1 </dev/null &'
stub notify-send 'case "$*" in *--action*) echo switch ;; esac'
"$AGENT" account state autoswitch claude >/dev/null 2>&1
eventually active_is work || fail "the second offer was not made or not carried out"
ok
cleanup_sandbox

begin "an offer that notify-send cannot show still reaches stderr and switches nothing"
two_accounts
stub notify-send 'echo switch; exit 1'
err=$("$AGENT" account state offer claude work "Main is at 97%" "Work is at 10%." 2>&1 >/dev/null)
[[ $err == "Main is at 97%: Work is at 10%." ]] || fail "stderr said: $err"
active_is main || fail "the account changed although the notification never showed"
ok
cleanup_sandbox

begin "without a desktop a notify-mode offer says how to switch"
two_accounts
unset DBUS_SESSION_BUS_ADDRESS
usage_record 0.97 0.1
err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
[[ $err == "Main is at 97% of a Claude limit: Work is at 10%. Switch new sessions to it with: cachyos-agent account use claude work" ]] || fail "stderr said: $err"
sleep 0.3
[[ ! -e $SANDBOX/calls/notify-send ]] || fail "a notification was sent without a desktop"
active_is main || fail "the account changed without a click"
ok
cleanup_sandbox

begin "without a desktop a message sent to a stderr nobody reads is said again where it can be read"
# `account use`, add, remove and rename start the usage refresh, and so the autoswitch, with
# stderr on /dev/null. The offer and the all-over message are all there is to tell the user.
for over in '0.97 0.1|Switch new sessions to it with: cachyos-agent account use claude work' '0.97 0.97|All Claude accounts are over 95%'; do
  two_accounts
  unset DBUS_SESSION_BUS_ADDRESS
  # shellcheck disable=SC2086 # two numbers
  usage_record ${over%%|*}
  "$AGENT" account state autoswitch claude 2>/dev/null
  [[ -z $(registry claude .alert) ]] || fail "an alert was kept for a message nobody read: $(registry claude .alert)"
  err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
  [[ $err == *"${over#*|}"* ]] || fail "the message was not said where stderr is kept: $err"
  err=$("$AGENT" account state autoswitch claude 2>&1 >/dev/null)
  [[ -z $err ]] || fail "the message was said again after it was read: $err"
  cleanup_sandbox
done
ok

begin "refresh brings the registry up to date with who each home is signed in as"
setup
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
FIX_ID=u-work FIX_EMAIL=new@example.com CLAUDE_CONFIG_DIR=$STATE/accounts/claude/work claude auth login >/dev/null
[[ $(registry claude '.accounts[1].email') == work@example.com ]] || fail "the test did not start from the old email"
"$AGENT" account state refresh
[[ $(registry claude '.accounts[1].email') == new@example.com ]] || fail "refresh did not pick up the new email"
ok
cleanup_sandbox

begin "a provider left out is the default agent's"
setup
stub cachyos-agent-default 'echo codex'
FIX_ID=u-cx FIX_EMAIL=cx@example.com "$AGENT" account add >/dev/null
FIX_ID=u-side FIX_EMAIL=side@example.com "$AGENT" account add Side >/dev/null
[[ $(registry codex '[.accounts[].id] | join(",")') == main,side ]] || fail "the codex accounts are wrong: $(registry codex .accounts)"
[[ $(<"$SANDBOX/logins") == "codex CODEX_HOME=unset
codex CODEX_HOME=$STATE/accounts/codex/.pending/login-"* ]] || fail "codex was not the CLI that signed in: $(<"$SANDBOX/logins")"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "add wrote a default although one was chosen"
"$AGENT" account use side >/dev/null 2>&1
[[ $(registry codex .active) == side && $("$AGENT" account home codex) == "$STATE/accounts/codex/side" ]] || fail "use did not act on codex"
[[ $("$AGENT" account mode auto 80) == "Codex switches new sessions"*"at 80%." ]] || fail "mode did not act on codex"
[[ $("$AGENT" account rename side Second) == "Renamed to Second."* ]] || fail "rename did not act on codex"
"$AGENT" account remove second >/dev/null 2>&1 </dev/null
[[ $(registry codex '.accounts | length') == 1 ]] || fail "remove did not act on codex"
stub cachyos-agent-default 'echo hermes'
if out=$("$AGENT" account use side 2>&1); then fail "a default agent without accounts supplied a provider"; fi
[[ $out == *"Usage: cachyos-agent account use"* ]] || fail "no usage: $out"
ok
cleanup_sandbox

begin "a provider left out is found when the default agent is chosen by an alias"
setup
stub notify-send
sign_in claude u-main main@example.com
sign_in claude u-work work@example.com Work
export CACHYOS_AGENT_DEFAULT=claude-code
"$AGENT" account use work >/dev/null 2>&1 || fail "use did not accept claude-code as the default agent"
[[ $(registry claude .active) == work ]] || fail "use did not act on claude"
[[ $("$AGENT" account mode auto 80) == "Claude switches new sessions"*"at 80%." ]] || fail "mode did not act on claude"
unset CACHYOS_AGENT_DEFAULT
ok
cleanup_sandbox

# ---- commands ------------------------------------------------------------------

begin "commands that edit the registry at the same moment all keep their edit"
setup
sign_in claude u-0 acct0@example.com
for i in {1..7}; do sign_in claude "u-$i" "acct$i@example.com" "Acct$i"; done
# The timer's autoswitch, the panel and a command typed at a prompt all read, change and save the
# registry. Without the lock around that, one writer's save drops another's edit.
for round in 1 2 3; do
  mapfile -t ids < <(registry claude '.accounts[1:][].id')
  for i in "${!ids[@]}"; do
    "$AGENT" account rename claude "${ids[i]}" "Round${round}x$i" >/dev/null 2>&1 &
  done
  wait
  expected=$(printf 'Round%sx%s\n' "$round" 0 "$round" 1 "$round" 2 "$round" 3 "$round" 4 "$round" 5 "$round" 6 | paste -sd,)
  [[ $(registry claude '[.accounts[1:][].label] | sort | join(",")') == "$expected" ]] \
    || fail "round $round: seven renames at once kept only: $(registry claude '[.accounts[].label] | join(",")')"
done
ok
cleanup_sandbox

begin "every account command is routed, documented and answers --help"
setup
json=$("$AGENT" commands --json --all)
for name in add use list remove rename mode; do
  jq -e --arg r "cachyos-agent account $name" '.commands[] | select(.route == $r and .hidden == false and (.summary | length) > 0)' <<<"$json" >/dev/null \
    || fail "account $name is missing or has no summary"
  [[ $("$AGENT" account "$name" --help) == "Usage: cachyos-agent account $name"* ]] || fail "account $name --help printed no usage"
  if "$AGENT" account "$name" --bogus >/dev/null 2>&1; then fail "account $name accepted --bogus"; fi
done
for name in home exec state; do
  jq -e --arg r "cachyos-agent account $name" '.commands[] | select(.route == $r and .hidden == true)' <<<"$json" >/dev/null || fail "account $name is not a hidden command"
done
group=$("$AGENT" account)
[[ $group == *"cachyos-agent account add"* && $group == *"cachyos-agent account list"* && $group != *"account state"* ]] || fail "group help: $group"
"$AGENT" commands --check >/dev/null || fail "commands --check rejects the account commands"
if "$AGENT" account state >/dev/null 2>&1; then fail "state without a command succeeded"; fi
ok
cleanup_sandbox
