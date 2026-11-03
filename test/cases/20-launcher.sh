#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The launcher: default, launch, prompt, install, shortcut, the desktop entry,
# the shell functions and the pi extension. Everything runs through the
# dispatcher or the real scripts; agent CLIs, terminals, pacman, paru and sudo
# are stubs, and the Plasma config is a file in the sandbox.
# shellcheck disable=SC2016 # a stub's body is a snippet for the stub to run, not for this shell
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

CA=$REPO_ROOT/bin/cachyos-agent
ALL_AGENTS=(pi omp opencode ori claude codex grok agy hermes copilot crush cursor-agent muse kimi qwen dsh mcode kiro-cli freebuff kilo devin amp commandcode)

# The tools the scripts need, and nothing else, so a test sees no agent CLI,
# terminal or clipboard tool that happens to be installed on the machine that
# runs it. Linked once per case, outside any sandbox.
TOOLS=$(mktemp -d)
SANDBOXES+=("$TOOLS")
for tool in bash env cat jq dirname readlink mkdir mktemp mv rm cp ln grep head tr sed cut sort basename touch chmod \
  script sleep mkfifo kwriteconfig6 kreadconfig6 desktop-file-validate fish node; do
  if path=$(command -v "$tool" 2>/dev/null); then
    ln -s "$path" "$TOOLS/$tool"
  fi
done

# setup: a sandbox whose PATH is its stubs, this checkout, then only $TOOLS (an
# older installed package must not answer for a command under test).
setup() {
  make_sandbox
  PATH=$SANDBOX/stubs:$REPO_ROOT/bin:$TOOLS
  export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$SANDBOX/no-data-dirs
  mkdir -p "$HOME/.config"
}

# run <command...>: run it with no terminal on stdin; set OUT, ERR and RC.
run() {
  local errfile=$SANDBOX/stderr.txt
  OUT=$("$@" 2>"$errfile" </dev/null) && RC=0 || RC=$?
  ERR=$(<"$errfile")
}

# tty_run <command...>: like run, but stdout and stderr are a terminal, as they
# are for a person typing the command. Sets OUT (stderr included, carriage
# returns removed) and RC. PTY_OK is false where script cannot provide a
# terminal, and a test that needs one skips.
PTY_OK=true
if ! SHELL=/bin/bash script -qec 'test -t 1 -a -t 2' /dev/null </dev/null >/dev/null 2>&1; then
  PTY_OK=false
fi
tty_run() {
  local cmd
  cmd=$(printf '%q ' "$@")
  OUT=$(SHELL=/bin/bash script -qec "$cmd" /dev/null </dev/null) && RC=0 || RC=$?
  OUT=${OUT//$'\r'/}
}

# last_call <stub>: the arguments of the stub's last call joined by '|', or
# <never called>.
last_call() {
  local file=$SANDBOX/calls/$1 line
  local -a args=() last=()
  local called=false
  if [[ -f $file ]]; then
    while IFS= read -r line; do
      if [[ -z $line ]]; then
        last=("${args[@]}")
        args=()
        called=true
      else
        args+=("$line")
      fi
    done <"$file"
  fi
  if $called; then
    local IFS='|'
    printf '%s\n' "${last[*]}"
  else
    echo "<never called>"
  fi
}

# call_count <stub>: how many times it ran.
call_count() {
  local file=$SANDBOX/calls/$1
  if [[ -f $file ]]; then
    grep -c '^$' "$file" || true
  else
    echo 0
  fi
}

expect() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
contains() { [[ $1 == *"$2"* ]] || fail "$3: [$1] lacks [$2]"; }
starts() { [[ $1 == "$2"* ]] || fail "$3: [$1] does not start with [$2]"; }
ends() { [[ $1 == *"$2" ]] || fail "$3: [$1] does not end with [$2]"; }
lacks() { [[ $1 != *"$2"* ]] || fail "$3: [$1] contains [$2]"; }

skip() { printf 'skip %s (%s)\n' "$CURRENT_TEST" "$1"; }

# window_stub <terminal>: a terminal that runs the command it is given after -e,
# as a real one does, and keeps what the command prints in $SANDBOX/window.
window_stub() {
  stub "$1" 'while [[ $1 != -e ]]; do shift; done; shift; "$@" >"${self%/stubs/*}/window" 2>&1'
}

# stub_agents <name...>: stubs that only record their argv.
stub_agents() {
  local name
  for name; do stub "$name"; done
}

# ---- default ---------------------------------------------------------------

begin "default prints nothing when no agent is chosen, then the saved one"
setup
run "$CA" default
expect "$RC:$OUT" "0:" "unset default"
mkdir -p "$XDG_CONFIG_HOME/cachyos-agent"
echo codex >"$XDG_CONFIG_HOME/cachyos-agent/default-agent"
run "$CA" default
expect "$OUT" "codex" "saved default"
CACHYOS_AGENT_DEFAULT=pi run "$CA" default
expect "$OUT" "pi" "CACHYOS_AGENT_DEFAULT overrides the file"
ok
cleanup_sandbox

begin "default <agent> saves it and launches"
setup
stub_agents claude cachyos-agent-launch
run "$CA" default claude
expect "$RC" 0 "exit status"
expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "claude" "saved agent"
expect "$(last_call cachyos-agent-launch)" "" "launch arguments"
expect "$(call_count cachyos-agent-launch)" 1 "launch calls"
run "$CA" default
expect "$OUT" "claude" "read back"
ok
cleanup_sandbox

begin "default accepts aliases and saves the agent id"
setup
stub_agents agy opencode cachyos-agent-launch
run "$CA" default gemini
expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "agy" "gemini is agy"
run "$CA" default open-code
expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "opencode" "open-code is opencode"
ok
cleanup_sandbox

begin "default rejects an unknown agent without saving anything"
setup
stub_agents cachyos-agent-launch
run "$CA" default notanagent
expect "$RC" 1 "exit status"
contains "$ERR" "Usage: cachyos-agent default" "usage on stderr"
contains "$ERR" "commandcode" "the choices are listed"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "wrote a default for an unknown agent"
expect "$(call_count cachyos-agent-launch)" 0 "launch must not run"
ok
cleanup_sandbox

begin "default: openclaw is not an agent here"
setup
stub_agents cachyos-agent-launch
run "$CA" default openclaw
expect "$RC" 1 "exit status"
contains "$ERR" "Usage: cachyos-agent default" "usage on stderr"
lacks "$ERR" "openclaw" "not listed as a choice"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "wrote a default for openclaw"
expect "$(call_count cachyos-agent-launch)" 0 "launch must not run"
ok
cleanup_sandbox

begin "default with a missing agent and no terminal opens one for the install"
setup
stub_agents konsole cachyos-agent-install cachyos-agent-launch
run "$CA" default codex
expect "$(last_call konsole)" "-p|tabtitle=CachyOS Agent|-e|cachyos-agent-default|--install|codex" "terminal arguments"
expect "$(call_count cachyos-agent-install)" 0 "the install runs inside the terminal, not here"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "saved a default before the install"
ok
cleanup_sandbox

begin "default --install installs, saves, clears the screen and launches inline"
setup
stub cachyos-agent-install 'touch "${self%/*}/codex"; chmod +x "${self%/*}/codex"'
stub cachyos-agent-launch
run "$CA" default --install codex
expect "$RC" 0 "exit status"
expect "$(last_call cachyos-agent-install)" "codex" "install arguments"
expect "$(last_call cachyos-agent-launch)" "--inline" "launch arguments"
expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "codex" "saved agent"
contains "$OUT" $'\033[2J' "screen cleared before the agent starts"
ok
cleanup_sandbox

begin "default fails and saves nothing when the install fails"
setup
stub cachyos-agent-install 'exit 1'
stub cachyos-agent-launch
run "$CA" default --install codex
expect "$RC" 1 "exit status"
contains "$ERR" "could not install Codex" "message"
[[ ! -e $XDG_CONFIG_HOME/cachyos-agent/default-agent ]] || fail "saved a default after a failed install"
expect "$(call_count cachyos-agent-launch)" 0 "launch must not run"
ok
cleanup_sandbox

begin "default --install holds its window after a failed install until Enter"
setup
# The window opened for an install closes when its command ends, so the reason
# an install failed (the vendor's command, a declined sudo) would flash by.
# stdin is a pipe that only the test writes to, to tell "waiting" from "gone".
stub cachyos-agent-install 'echo "npm install -g example" >&2; exit 1'
stub cachyos-agent-launch
mkfifo "$SANDBOX/enter"
"$CA" default --install pi <"$SANDBOX/enter" >/dev/null 2>"$SANDBOX/window" &
window=$!
exec 3>"$SANDBOX/enter"
for _ in {1..50}; do
  kill -0 "$window" 2>/dev/null || break
  [[ $(<"$SANDBOX/window") == *"Press Enter"* ]] && break
  sleep 0.1
done
contains "$(<"$SANDBOX/window")" "npm install -g example" "the install's own advice"
contains "$(<"$SANDBOX/window")" "could not install Pi" "the failure"
contains "$(<"$SANDBOX/window")" "Press Enter" "the prompt"
if kill -0 "$window" 2>/dev/null; then
  echo >&3
else
  fail "the window closed without waiting for Enter"
fi
exec 3>&-
wait "$window" && RC=0 || RC=$?
expect "$RC" 1 "exit status once Enter is pressed"
expect "$(call_count cachyos-agent-launch)" 0 "launch must not run"
ok
cleanup_sandbox

begin "default at a terminal does not wait after a failed install"
setup
# Only the window opened for the install is held; at your own terminal the
# error is already on screen and the prompt returns.
if ! $PTY_OK; then
  skip "script cannot give this process a terminal"
else
  stub cachyos-agent-install 'exit 1'
  tty_run "$CA" default pi
  expect "$RC" 1 "exit status"
  contains "$OUT" "could not install Pi" "the failure"
  lacks "$OUT" "Press Enter" "no wait outside the install window"
  ok
fi
cleanup_sandbox

begin "default with a missing agent at a terminal installs it right there"
setup
if ! SHELL=/bin/bash script -qec 'test -t 0' /dev/null </dev/null >/dev/null 2>&1; then
  skip "script cannot give this process a terminal"
else
  stub cachyos-agent-install 'touch "${self%/*}/codex"; chmod +x "${self%/*}/codex"'
  stub cachyos-agent-launch
  stub konsole
  SHELL=/bin/bash script -qec "$CA default codex" /dev/null </dev/null >/dev/null
  expect "$(last_call cachyos-agent-install)" "codex" "install arguments"
  expect "$(call_count konsole)" 0 "no extra terminal at a terminal"
  expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "codex" "saved agent"
  expect "$(last_call cachyos-agent-launch)" "" "launch arguments"
  ok
fi
cleanup_sandbox

begin "default counts a command in ~/.local/bin as installed"
setup
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\n' >"$HOME/.local/bin/hermes"
chmod +x "$HOME/.local/bin/hermes"
stub_agents konsole cachyos-agent-install cachyos-agent-launch
run "$CA" default hermes
expect "$(call_count konsole)" 0 "no install terminal"
expect "$(call_count cachyos-agent-install)" 0 "no install"
expect "$(<"$XDG_CONFIG_HOME/cachyos-agent/default-agent")" "hermes" "saved agent"
ok
cleanup_sandbox

# ---- launch ----------------------------------------------------------------

begin "launch with no default exits 1 and says how to choose one"
setup
run "$CA" launch --inline
expect "$RC" 1 "exit status"
contains "$ERR" "cachyos-agent default <name>" "hint"
lacks "$ERR" "Agents:" "no list without --pick"
ok
cleanup_sandbox

begin "launch --pick with no default lists the agents and how to choose"
setup
run "$CA" launch --pick
expect "$RC" 1 "exit status"
contains "$ERR" "cachyos-agent default <name>" "hint"
for agent in "${ALL_AGENTS[@]}"; do contains "$ERR" "$agent" "the list names $agent"; done
ok
cleanup_sandbox

begin "launch --inline runs claude with its auto mode and says so"
setup
stub claude
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$RC" 0 "exit status"
expect "$(last_call claude)" "--permission-mode|auto" "claude arguments"
contains "$ERR" "Claude Code with --permission-mode auto" "announcement"
ok
cleanup_sandbox

begin "launch --inline passes each agent's own auto flags and prompt form"
setup
stub_agents claude codex opencode hermes
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --prompt "hello there"
expect "$(last_call claude)" "--permission-mode|auto|--|hello there" "claude"
CACHYOS_AGENT_DEFAULT=codex run "$CA" launch --inline --prompt "hello there"
expect "$(last_call codex)" "--approve-for-me|--|hello there" "codex"
CACHYOS_AGENT_DEFAULT=opencode run "$CA" launch --inline --prompt "hello there"
expect "$(last_call opencode)" "--auto|--prompt|hello there" "opencode"
CACHYOS_AGENT_DEFAULT=hermes run "$CA" launch --inline --prompt "hello there"
expect "$(last_call hermes)" "chat|--yolo|--tui|--query=hello there" "hermes with a prompt"
CACHYOS_AGENT_DEFAULT=hermes run "$CA" launch --inline
expect "$(last_call hermes)" "--yolo" "hermes without a prompt"
ok
cleanup_sandbox

begin "hermes does not inherit the session source of the run that launched it"
setup
stub hermes 'printf "%s" "${HERMES_SESSION_SOURCE-unset}" >"${self%/stubs/*}/source"'
HERMES_SESSION_SOURCE=gateway CACHYOS_AGENT_DEFAULT=hermes run "$CA" launch --inline --prompt "hi"
expect "$(<"$SANDBOX/source")" "unset" "HERMES_SESSION_SOURCE inside hermes"
HERMES_SESSION_SOURCE=gateway CACHYOS_AGENT_DEFAULT=hermes run "$CA" launch --inline
expect "$(<"$SANDBOX/source")" "gateway" "without a prompt hermes is started as before"
ok
cleanup_sandbox

begin "a prompt that starts with a dash and holds spaces and quotes reaches the agent intact"
setup
stub_agents claude opencode pi qwen
tricky='-n it'\''s "quoted" $HOME `ls` * and --yolo'
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --prompt "$tricky"
expect "$(last_call claude)" "--permission-mode|auto|--|$tricky" "claude"
CACHYOS_AGENT_DEFAULT=qwen run "$CA" launch --inline --prompt "$tricky"
expect "$(last_call qwen)" "--yolo|--prompt-interactive=$tricky" "qwen binds the value"
CACHYOS_AGENT_DEFAULT=pi run "$CA" launch --inline --prompt "$tricky"
expect "$(last_call pi)" "--|$tricky" "pi stops option parsing first"
CACHYOS_AGENT_DEFAULT=claude run "$CA" prompt --inline -- -dash "two words" 'q"uote'
expect "$(last_call claude)" '--permission-mode|auto|--|-dash two words q"uote' "through cachyos-agent prompt"
ok
cleanup_sandbox

begin "prompt without --inline opens the terminal, with no arguments it shows usage"
setup
stub opencode
window_stub konsole
CACHYOS_AGENT_DEFAULT=opencode run "$CA" prompt "Review this project"
expect "$RC" 0 "exit status"
starts "$(last_call konsole)" "-p|tabtitle=CachyOS Agent|-e|" "terminal arguments"
expect "$(last_call opencode)" "--auto|--prompt|Review this project" "agent arguments in the window"
run "$CA" prompt
expect "$RC" 1 "no prompt is an error"
contains "$ERR" "Usage: cachyos-agent prompt" "usage"
run "$CA" prompt --help
expect "$RC" 0 "--help"
contains "$OUT" "Usage: cachyos-agent prompt" "help text"
ok
cleanup_sandbox

begin "launch opens the configured terminal with the title and command words"
setup
stub opencode
window_stub alacritty
TERMINAL=alacritty CACHYOS_AGENT_DEFAULT=opencode run "$CA" launch
starts "$(last_call alacritty)" "-T|CachyOS Agent|-e|" "alacritty arguments"
expect "$(last_call opencode)" "--auto" "agent arguments in the window"
ok
cleanup_sandbox

begin "a terminal launch announces the unattended mode in the new window"
setup
# The shortcut, the panel button and the crash watcher discard the launcher's
# stderr, so the line has to be printed where the agent starts.
stub claude
stub pi
window_stub konsole
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch
expect "$RC" 0 "exit status"
contains "$(<"$SANDBOX/window")" "starting Claude Code with --permission-mode auto, which does not stop to ask before acting" "announcement in the window"
expect "$(last_call claude)" "--permission-mode|auto" "claude arguments"
lacks "$ERR" "starting" "the launcher's own stderr is not where it is read"
CACHYOS_AGENT_DEFAULT=pi run "$CA" launch
contains "$(<"$SANDBOX/window")" "starting Pi (it has no auto-approve flag)" "an agent without a flag says so"
ok
cleanup_sandbox

begin "the announcement comes before the clipboard fallback's own text"
setup
stub dsh
window_stub konsole
CACHYOS_AGENT_DEFAULT=dsh run "$CA" launch --prompt "do the thing"
window=$(<"$SANDBOX/window")
starts "$window" "cachyos-agent: starting DeepSeek Harness with DSH_PERMISSION_MODE=danger-full-access" "announcement first"
contains "$window" "do the thing" "then the prompt"
ok
cleanup_sandbox

begin "launch --agent beats the default, and a missing agent is refused"
setup
stub_agents claude hermes
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --agent hermes
expect "$(call_count claude)" 0 "the default must not run"
expect "$(last_call hermes)" "--yolo" "hermes arguments"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --agent codex
expect "$RC" 1 "exit status"
contains "$ERR" "Codex is not installed" "message"
contains "$ERR" "cachyos-agent install codex" "install hint"
expect "$(call_count claude)" 0 "no fallback to the default"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --agent nonsense
expect "$RC" 1 "unknown agent"
contains "$ERR" "Unsupported agent: nonsense" "message"
ok
cleanup_sandbox

begin "launch refuses an unknown default and stray arguments"
setup
CACHYOS_AGENT_DEFAULT=bogus run "$CA" launch --inline
expect "$RC" 1 "unknown default"
contains "$ERR" "Unsupported agent: bogus" "names the bad default"
mkdir -p "$XDG_CONFIG_HOME/cachyos-agent"
echo bogus-saved >"$XDG_CONFIG_HOME/cachyos-agent/default-agent"
run "$CA" launch --inline
expect "$RC" 1 "unknown saved default"
contains "$ERR" "Unsupported agent: bogus-saved" "names the bad saved default"
run "$CA" launch --inline "do things"
expect "$RC" 1 "stray argument"
contains "$ERR" 'cachyos-agent prompt "do things"' "points to prompt"
ok
cleanup_sandbox

# run swaps stderr for a file, so the tests above never reach the branch of a
# refusal that a person at a terminal gets. These run on a terminal.
begin "at a terminal a refusal says what is wrong and what to do"
setup
if ! $PTY_OK; then
  skip "script cannot give this process a terminal"
else
  stub claude
  CACHYOS_AGENT_DEFAULT=claude tty_run "$CA" launch --inline --agent nonsense
  expect "$RC" 1 "unknown agent"
  contains "$OUT" "Unsupported agent: nonsense" "unknown agent: the problem"
  contains "$OUT" "Agents: pi omp opencode" "unknown agent: the choices"
  CACHYOS_AGENT_DEFAULT=claude tty_run "$CA" launch --inline --agent codex
  expect "$RC" 1 "missing agent"
  contains "$OUT" "Codex is not installed" "missing agent: the problem"
  contains "$OUT" "cachyos-agent install codex" "missing agent: the way out"
  CACHYOS_AGENT_DEFAULT=bogus tty_run "$CA" launch --inline
  contains "$OUT" "Unsupported agent: bogus" "bad default"
  tty_run "$CA" launch --pick
  expect "$RC" 1 "no default"
  contains "$OUT" "No default agent" "no default: the problem"
  contains "$OUT" "cachyos-agent default <name>" "no default: the way out"
  contains "$OUT" "Agents: pi omp opencode" "--pick lists the agents"
  ok
fi
cleanup_sandbox

begin "launch prints the refusal and also notifies when it has no terminal and a bus"
setup
export DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null
stub notify-send
run "$CA" launch --pick
expect "$RC" 1 "exit status"
contains "$(last_call notify-send)" "No default agent" "notification summary"
contains "$(last_call notify-send)" "cachyos-agent default <name>" "notification body"
contains "$ERR" "No default agent" "stderr summary, for a script or an agent shell"
contains "$ERR" "cachyos-agent default <name>" "stderr hint"
contains "$ERR" "Agents: pi omp opencode" "--pick lists the agents on stderr"
ok
cleanup_sandbox

begin "launch prints a refusal once when there is no bus to notify"
setup
run "$CA" launch --pick
expect "$RC" 1 "exit status"
expect "$(grep -c 'No default agent' <<<"$ERR")" 1 "the summary appears once"
ok
cleanup_sandbox

begin "every agent id starts, with and without a prompt"
setup
stub wl-copy 'cat >/dev/null'
for agent in "${ALL_AGENTS[@]}"; do stub "$agent"; done
for agent in "${ALL_AGENTS[@]}"; do
  run "$CA" launch --inline --agent "$agent"
  [[ $RC == 0 && $(call_count "$agent") == 1 ]] || fail "$agent did not start without a prompt (rc $RC): $ERR"
  run "$CA" launch --inline --agent "$agent" --prompt "fix it"
  [[ $RC == 0 && $(call_count "$agent") == 2 ]] || fail "$agent did not start with a prompt (rc $RC): $ERR"
done
ok
cleanup_sandbox

begin "launch --inline per-agent argv for the rest of the table"
setup
for agent in "${ALL_AGENTS[@]}"; do stub "$agent"; done
stub wl-copy 'cat >/dev/null'
declare -A WITH_PROMPT=(
  [agy]="--dangerously-skip-permissions|--prompt-interactive|P Q"
  [copilot]="--allow-all|--interactive|P Q"
  [crush]="run|P Q"
  [grok]="--permission-mode|bypassPermissions|--|P Q"
  [cursor-agent]="--yolo|--trust|agent|--|P Q"
  [muse]="--approval-mode|never|--|P Q"
  [omp]="--auto-approve|--|P Q"
  [ori]="code|--interactive|--prompt|P Q"
  [pi]="--|P Q"
  [kimi]="--prompt|P Q"
  [qwen]="--yolo|--prompt-interactive=P Q"
  [mcode]="--|P Q"
  [kiro-cli]="chat|--trust-all-tools|--|P Q"
  [kilo]="--auto|--prompt=P Q"
  [devin]="--permission-mode|dangerous|--respect-workspace-trust|false|--|P Q"
  [commandcode]="--yolo|--|P Q"
  [dsh]="web"
  [freebuff]=""
)
for agent in "${!WITH_PROMPT[@]}"; do
  run "$CA" launch --inline --agent "$agent" --prompt "P Q"
  expect "$(last_call "$agent")" "${WITH_PROMPT[$agent]}" "$agent with a prompt"
done
declare -A NO_PROMPT=(
  [crush]="--yolo" [kimi]="--yolo" [ori]="code" [pi]="" [mcode]="" [freebuff]="" [dsh]="web"
  [kiro-cli]="chat|--trust-all-tools" [cursor-agent]="--yolo|--trust" [amp]="--dangerously-allow-all"
  [devin]="--permission-mode|dangerous|--respect-workspace-trust|false"
  [claude]="--permission-mode|auto" [codex]="--approve-for-me" [opencode]="--auto" [grok]="--permission-mode|bypassPermissions"
  [agy]="--dangerously-skip-permissions" [copilot]="--allow-all" [muse]="--approval-mode|never" [omp]="--auto-approve"
  [qwen]="--yolo" [kilo]="--auto" [commandcode]="--yolo"
)
for agent in "${!NO_PROMPT[@]}"; do
  run "$CA" launch --inline --agent "$agent"
  expect "$(last_call "$agent")" "${NO_PROMPT[$agent]}" "$agent without a prompt"
done
ok
cleanup_sandbox

begin "an agent without an auto-approve flag is announced as such"
setup
stub pi
CACHYOS_AGENT_DEFAULT=pi run "$CA" launch --inline
contains "$ERR" "starting Pi (it has no auto-approve flag)" "announcement"
ok
cleanup_sandbox

begin "amp takes its first message on stdin, with its flag"
setup
stub amp 'cat >"${self%/stubs/*}/amp-stdin"'
run "$CA" launch --inline --agent amp --prompt $'first "message"'
expect "$(last_call amp)" "--dangerously-allow-all" "amp arguments"
expect "$(<"$SANDBOX/amp-stdin")" 'first "message"' "amp stdin"
ok
cleanup_sandbox

begin "dsh runs with full access and the prompt goes to the clipboard"
setup
stub dsh 'printf "%s" "${DSH_PERMISSION_MODE-}" >"${self%/stubs/*}/mode"'
stub wl-copy 'cat >"${self%/stubs/*}/clip"'
run "$CA" launch --inline --agent dsh --prompt "do -the thing"
expect "$(last_call dsh)" "web" "dsh arguments"
expect "$(<"$SANDBOX/mode")" "danger-full-access" "permission mode"
expect "$(<"$SANDBOX/clip")" "do -the thing" "clipboard"
run "$CA" launch --inline --agent dsh
expect "$(call_count wl-copy)" 1 "no clipboard write without a prompt"
ok
cleanup_sandbox

begin "a prompt for an agent that cannot take one goes to Klipper without wl-copy"
setup
stub_agents freebuff qdbus6
run "$CA" launch --inline --agent freebuff --prompt "-hello there"
expect "$(last_call qdbus6)" "org.kde.klipper|/klipper|setClipboardContents|-hello there" "qdbus6 arguments"
expect "$(call_count freebuff)" 1 "freebuff started"
ok
cleanup_sandbox

begin "with no clipboard tool the prompt is shown in the agent's own window"
setup
stub_agents freebuff
run "$CA" launch --inline --agent freebuff --prompt "paste me"
expect "$RC" 0 "exit status"
contains "$OUT" "paste me" "the prompt is printed"
contains "$OUT" "Freebuff has no way to take a starting prompt" "explanation"
expect "$(last_call freebuff)" "" "freebuff still starts"
ok
cleanup_sandbox

begin "launch --inline from a home with ~/Work starts there"
setup
stub claude 'pwd >"${self%/stubs/*}/cwd"'
cd "$HOME"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/cwd")" "$HOME" "no ~/Work yet"
mkdir "$HOME/Work"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/cwd")" "$HOME/Work" "started in ~/Work"
mkdir "$HOME/Work/project"
cd "$HOME/Work/project"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/cwd")" "$HOME/Work/project" "another directory is kept"
cd "$REPO_ROOT"
ok
cleanup_sandbox

begin "launch runs the user's own ~/.local/bin install when PATH lacks it"
setup
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" >"%s/user-install"\n' "$SANDBOX" >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --prompt "hi"
expect "$RC" 0 "exit status"
expect "$(tr '\n' '|' <"$SANDBOX/user-install")" "--permission-mode|auto|--|hi|" "arguments seen by the user's install"
ok
cleanup_sandbox

begin "launch pins the active account's home when an accounts command exists"
setup
for agent in claude codex grok; do
  stub "$agent" 'printf "%s|%s|%s|%s" "${CLAUDE_CONFIG_DIR-unset}" "${CODEX_HOME-unset}" "${GROK_HOME-unset}" "${CACHYOS_AGENT_CLAUDE_HOME-unset}" >"${self%/stubs/*}/env"'
done
stub cachyos-agent-account-home 'case $1 in claude) printf "/acct/claude-work" ;; codex) printf "/acct/codex-work" ;; grok) ;; esac'
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "/acct/claude-work|unset|unset|/acct/claude-work" "claude"
expect "$(last_call cachyos-agent-account-home)" "claude" "account-home arguments"
CACHYOS_AGENT_DEFAULT=codex run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "unset|/acct/codex-work|unset|unset" "codex"
CACHYOS_AGENT_DEFAULT=grok run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "unset|unset|unset|unset" "grok on its primary account sets nothing"
# A parent session's pin gives way to the current selection ...
CLAUDE_CONFIG_DIR=/acct/old CACHYOS_AGENT_CLAUDE_HOME=/acct/old CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "/acct/claude-work|unset|unset|/acct/claude-work" "inherited pin"
# ... but a home the user set by hand does not, and no stale pin follows it.
CLAUDE_CONFIG_DIR=/mine CACHYOS_AGENT_CLAUDE_HOME=/acct/stale CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "/mine|unset|unset|unset" "explicit home"
ok
cleanup_sandbox

begin "launch pins the primary account explicitly when the selected account is the primary one"
setup
stub claude 'printf "%s|%s" "${CLAUDE_CONFIG_DIR-unset}" "${CACHYOS_AGENT_CLAUDE_HOME-unset}" >"${self%/stubs/*}/env"'
stub cachyos-agent-account-home
CLAUDE_CONFIG_DIR=/acct/old CACHYOS_AGENT_CLAUDE_HOME=/acct/old CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline
expect "$(<"$SANDBOX/env")" "unset|" "the primary account is pinned as empty, so the parent's account is dropped"
ok
cleanup_sandbox

begin "launch carries the account pin into the terminal command"
setup
stub_agents claude konsole
stub cachyos-agent-account-home 'printf "/acct/work"'
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch
ends "$(last_call konsole)" "|env|-u|CLAUDE_CONFIG_DIR|CACHYOS_AGENT_CLAUDE_HOME=/acct/work|CLAUDE_CONFIG_DIR=/acct/work|claude|--permission-mode|auto" "terminal command"
ok
cleanup_sandbox

begin "launch skips account pinning when there is no accounts command"
setup
# A private tree without cachyos-agent-account-home, whatever the checkout holds.
TREE=$SANDBOX/tree
mkdir -p "$TREE/bin" "$TREE/lib" "$TREE/data"
cp "$REPO_ROOT"/bin/cachyos-agent-{launch,default} "$TREE/bin/"
cp "$REPO_ROOT"/lib/{common,launcher}.sh "$TREE/lib/"
cp "$REPO_ROOT/VERSION" "$TREE/"
PATH=$SANDBOX/stubs:$TREE/bin:$TOOLS
stub claude 'printf "%s" "${CLAUDE_CONFIG_DIR-unset}" >"${self%/stubs/*}/env"'
CACHYOS_AGENT_DEFAULT=claude CLAUDE_CONFIG_DIR=/mine run "$TREE/bin/cachyos-agent-launch" --inline
expect "$RC" 0 "exit status"
expect "$(<"$SANDBOX/env")" "/mine" "the environment passes through"
CACHYOS_AGENT_DEFAULT=claude run "$TREE/bin/cachyos-agent-launch" --inline
expect "$(<"$SANDBOX/env")" "unset" "nothing is set"
ok
cleanup_sandbox

# ---- launch --local --------------------------------------------------------

# choose_local_model <name>: choose the active model the way `cachyos-agent local use` does.
choose_local_model() {
  mkdir -p "$XDG_STATE_HOME/cachyos-agent/local"
  printf '%s\n' "$1" >"$XDG_STATE_HOME/cachyos-agent/local/active"
}

# stub_opencode <version>: an opencode that prints <version> for --version and
# otherwise saves the inline config it was given.
stub_opencode() {
  stub opencode 'if [[ ${1-} == --version ]]; then echo "'"$1"'"; else printf "%s" "${OPENCODE_CONFIG_CONTENT-}" >"${self%/stubs/*}/opencode-config"; fi'
  }

begin "launch --local without a chosen model says how to choose one"
setup
stub_opencode 2.2.5
run "$CA" launch --inline --local
expect "$RC" 1 "exit status"
contains "$ERR" "cachyos-agent local use <model>" "hint"
expect "$(call_count opencode)" 0 "nothing started"
ok
cleanup_sandbox

begin "launch --local points OpenCode at Ollama through inline config"
setup
stub_opencode 2.2.5
choose_local_model 'qwen3:8b'
CACHYOS_AGENT_DEFAULT=opencode run "$CA" launch --inline --local --prompt "go"
expect "$RC" 0 "exit status"
expect "$(last_call opencode)" "--auto|--prompt|go|--standalone" "OpenCode 2 gets a private server"
config=$(<"$SANDBOX/opencode-config")
jq -e '.model == "ollama/qwen3:8b"' <<<"$config" >/dev/null || fail "model is not ollama/qwen3:8b: $config"
jq -e '.provider.ollama | .npm == "@ai-sdk/openai-compatible" and .options.baseURL == "http://127.0.0.1:11434/v1"' <<<"$config" >/dev/null \
  || fail "provider is not the Ollama endpoint: $config"
jq -e '.provider.ollama.models | keys == ["qwen3:8b"]' <<<"$config" >/dev/null || fail "models are not just the chosen one: $config"
contains "$ERR" "local model qwen3:8b (http://127.0.0.1:11434/v1)" "announcement names the model"
ok
cleanup_sandbox

begin "launch --local leaves --standalone off for OpenCode 1 and takes --local-model over the chosen one"
setup
stub_opencode 1.19.5
choose_local_model 'qwen3:8b'
CACHYOS_AGENT_DEFAULT=opencode run "$CA" launch --inline --local-model 'hf.co/org/model:Q4_K_M'
expect "$(last_call opencode)" "--auto" "OpenCode 1 arguments"
jq -e '.model == "ollama/hf.co/org/model:Q4_K_M" and (.provider.ollama.models | keys == ["hf.co/org/model:Q4_K_M"])' \
  <"$SANDBOX/opencode-config" >/dev/null || fail "--local-model was not used: $(<"$SANDBOX/opencode-config")"
ok
cleanup_sandbox

begin "launch --local registers Ollama in pi for the run only"
setup
stub pi 'printf "%s|%s" "${CACHYOS_AGENT_LOCAL_MODEL-unset}" "${CACHYOS_AGENT_LOCAL_URL-unset}" >"${self%/stubs/*}/pi-env"'
choose_local_model 'qwen3:8b'
CACHYOS_AGENT_DEFAULT=pi run "$CA" launch --inline --local --prompt "-go now"
expect "$RC" 0 "exit status"
expect "$(last_call pi)" "--extension|$REPO_ROOT/data/pi-ollama.ts|--provider|ollama|--model|qwen3:8b|--|-go now" "pi arguments"
expect "$(<"$SANDBOX/pi-env")" "qwen3:8b|http://127.0.0.1:11434/v1" "extension environment"
[[ -f $REPO_ROOT/data/pi-ollama.ts ]] || fail "the extension is not shipped"
ok
cleanup_sandbox

begin "launch --local falls back to pi, then OpenCode, when the default cannot run a local model"
setup
stub_agents claude pi
stub_opencode 2.2.5
choose_local_model 'qwen3:8b'
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --local
expect "$(call_count claude)" 0 "the default must not run"
expect "$(call_count pi)" 1 "pi comes first"
rm "$SANDBOX/stubs/pi"
run "$CA" launch --inline --local --agent claude
expect "$(last_call opencode)" "--auto|--standalone" "OpenCode without pi"
rm "$SANDBOX/stubs/opencode"
CACHYOS_AGENT_DEFAULT=claude run "$CA" launch --inline --local
expect "$RC" 1 "no local-capable agent"
contains "$ERR" "cachyos-agent install opencode" "install hint"
expect "$(call_count claude)" 0 "claude must not run"
ok
cleanup_sandbox

begin "launch --local needs no default agent"
setup
stub pi
choose_local_model 'qwen3:8b'
run "$CA" launch --inline --local
expect "$RC" 0 "exit status"
expect "$(call_count pi)" 1 "pi started"
ok
cleanup_sandbox

begin "launch --local opens the terminal like any launch"
setup
stub_agents pi konsole
choose_local_model 'qwen3:8b'
run "$CA" launch --local
contains "$(last_call konsole)" "|env|CACHYOS_AGENT_LOCAL_MODEL=qwen3:8b|CACHYOS_AGENT_LOCAL_URL=http://127.0.0.1:11434/v1|pi|--extension|" "terminal command"
ok
cleanup_sandbox

begin "a terminal launch announces a local model and keeps a tricky prompt intact"
setup
stub pi
window_stub konsole
choose_local_model 'qwen3:8b'
tricky='-n it'\''s "quoted" $HOME `ls` *'
run "$CA" launch --local --prompt "$tricky"
contains "$(<"$SANDBOX/window")" "starting Pi on local model qwen3:8b (http://127.0.0.1:11434/v1)" "announcement names the model"
ends "$(last_call pi)" "--|$tricky" "the prompt reaches the agent through the wrapper"
ok
cleanup_sandbox

# ---- install ---------------------------------------------------------------

begin "install uses pacman for a repository package, in the visible terminal"
setup
stub pacman
stub sudo 'touch "${self%/*}/claude"; chmod +x "${self%/*}/claude"'
run "$CA" install claude
expect "$RC" 0 "exit status"
expect "$(last_call pacman)" "-Si|--|claude-code" "the package is looked up first"
expect "$(last_call sudo)" "pacman|-S|--needed|claude-code" "sudo arguments"
expect "$(call_count sudo)" 1 "sudo calls"
ok
cleanup_sandbox

begin "install maps the agents the repositories carry"
setup
stub pacman
stub sudo
declare -A REPO_PACKAGES=([opencode]=opencode [codex]=openai-codex [copilot]=github-copilot-cli [qwen]=qwen-code [hermes]=hermes-agent)
for agent in "${!REPO_PACKAGES[@]}"; do
  run "$CA" install "$agent"
  expect "$(last_call sudo)" "pacman|-S|--needed|${REPO_PACKAGES[$agent]}" "$agent package"
done
ok
cleanup_sandbox

begin "install says so when the repositories lack the package, and never runs sudo"
setup
stub pacman 'exit 1'
stub sudo
run "$CA" install claude
expect "$RC" 1 "exit status"
contains "$ERR" "claude-code is not in the enabled pacman repositories" "message"
expect "$(call_count sudo)" 0 "sudo calls"
ok
cleanup_sandbox

begin "install uses paru for an AUR package and never --noconfirm"
setup
stub paru 'touch "${self%/*}/crush"; chmod +x "${self%/*}/crush"'
stub sudo
run "$CA" install crush
expect "$RC" 0 "exit status"
expect "$(last_call paru)" "-S|--needed|crush" "paru arguments"
contains "$ERR" "read the PKGBUILD" "review reminder"
expect "$(call_count sudo)" 0 "sudo calls"
declare -A AUR_PACKAGES=([omp]=oh-my-pi [agy]=antigravity-cli [grok]=grok-build [kilo]=kilo-bin [amp]=ampcode
  [commandcode]=command-code [kiro-cli]=kiro-cli [cursor-agent]=cursor-cli)
for agent in "${!AUR_PACKAGES[@]}"; do
  run "$CA" install "$agent"
  expect "$(last_call paru)" "-S|--needed|${AUR_PACKAGES[$agent]}" "$agent package"
done
ok
cleanup_sandbox

begin "install without paru points at the AUR page"
setup
run "$CA" install crush
expect "$RC" 1 "exit status"
contains "$ERR" "https://aur.archlinux.org/packages/crush" "AUR page"
ok
cleanup_sandbox

begin "install prints the vendor's command and runs nothing for an agent without a package"
setup
stub_agents sudo pacman paru npm curl
run "$CA" install pi
expect "$RC" 1 "exit status"
contains "$ERR" "npm install -g --ignore-scripts @earendil-works/pi-coding-agent" "pi command"
run "$CA" install kimi
contains "$ERR" "npm install -g @moonshot-ai/kimi-code" "kimi command"
run "$CA" install ori
expect "$RC" 1 "ori exit status"
contains "$ERR" "https://openrouter.ai/docs/guides/ori/overview" "ori page"
contains "$ERR" "never pipes one into a shell" "script warning"
for tool in sudo pacman paru npm curl; do expect "$(call_count $tool)" 0 "$tool must not run"; done
ok
cleanup_sandbox

begin "install does nothing for an agent that is already there"
setup
stub_agents claude sudo paru
run "$CA" install claude
expect "$RC" 0 "exit status"
contains "$OUT" "Claude Code is already installed" "message"
expect "$(call_count sudo)" 0 "sudo calls"
ok
cleanup_sandbox

begin "install fails when the package did not provide the command"
setup
stub_agents pacman sudo
run "$CA" install codex
expect "$RC" 1 "exit status"
contains "$ERR" "Codex was installed but 'codex' is not on PATH" "message"
ok
cleanup_sandbox

begin "install rejects an unknown agent and a missing argument"
setup
run "$CA" install nonsense
expect "$RC" 1 "unknown agent"
run "$CA" install
expect "$RC" 1 "no agent"
contains "$ERR" "Usage: cachyos-agent install" "usage"
ok
cleanup_sandbox

begin "install has a plan for every agent id"
setup
for agent in "${ALL_AGENTS[@]}"; do
  run "$CA" install "$agent"
  lacks "$ERR" "unbound variable" "install $agent"
  [[ $RC == 1 ]] || fail "install $agent exited $RC with nothing installed"
done
ok
cleanup_sandbox

# ---- shortcut --------------------------------------------------------------

RC_FILE_NAME=kglobalshortcutsrc

begin "shortcut set writes the Plasma launch entry and show reads it back"
setup
if ! command -v kwriteconfig6 >/dev/null; then
  skip "kwriteconfig6 is not installed"
else
  run "$CA" shortcut show
  expect "$OUT" "not set" "nothing bound yet"
  run "$CA" shortcut set
  expect "$RC" 0 "exit status"
  contains "$OUT" "Meta+Ctrl+Shift+A" "message names the combo"
  contains "$OUT" "log out" "message says when it applies"
  expect "$(<"$XDG_CONFIG_HOME/$RC_FILE_NAME")" $'[services][cachyos-agent.desktop]\n_launch=Meta+Ctrl+Shift+A' "file content"
  run "$CA" shortcut show
  expect "$OUT" "Meta+Ctrl+Shift+A" "show"
  run "$CA" shortcut
  expect "$OUT" "Meta+Ctrl+Shift+A" "show is the default action"
  ok
fi
cleanup_sandbox

begin "shortcut set replaces the combo, unset removes it, other groups stay"
setup
if ! command -v kwriteconfig6 >/dev/null; then
  skip "kwriteconfig6 is not installed"
else
  printf '[kwin]\nWindow Close=Alt+F4\n\n[services][org.kde.konsole.desktop]\n_launch=Ctrl+Alt+T\n' >"$XDG_CONFIG_HOME/$RC_FILE_NAME"
  run "$CA" shortcut set Meta+Alt+A
  expect "$RC" 0 "exit status"
  run "$CA" shortcut set Ctrl+Shift+F9
  rc_file=$(<"$XDG_CONFIG_HOME/$RC_FILE_NAME")
  contains "$rc_file" $'[services][cachyos-agent.desktop]\n_launch=Ctrl+Shift+F9' "the new combo"
  lacks "$rc_file" "Meta+Alt+A" "the old combo is gone"
  contains "$rc_file" "Window Close=Alt+F4" "kwin group kept"
  contains "$rc_file" $'[services][org.kde.konsole.desktop]\n_launch=Ctrl+Alt+T' "another application's shortcut kept"
  run "$CA" shortcut unset
  expect "$RC" 0 "unset exit status"
  contains "$OUT" "Shortcut removed" "unset message"
  rc_file=$(<"$XDG_CONFIG_HOME/$RC_FILE_NAME")
  lacks "$rc_file" "cachyos-agent" "the entry is removed"
  contains "$rc_file" "_launch=Ctrl+Alt+T" "konsole kept"
  run "$CA" shortcut show
  expect "$OUT" "not set" "show after unset"
  run "$CA" shortcut unset
  expect "$RC:$OUT" "0:No shortcut is set." "unset twice"
  ok
fi
cleanup_sandbox

begin "shortcut refuses anything that is not a modifier plus a key"
setup
if ! command -v kwriteconfig6 >/dev/null; then
  skip "kwriteconfig6 is not installed"
else
  for combo in A F5 Meta Meta+Ctrl Super+A Meta+Alt+ Meta++A 'Meta+A B' 'Meta+A;touch x' '-h' ''; do
    run "$CA" shortcut set "$combo"
    [[ $RC == 1 ]] || fail "accepted [$combo]"
  done
  [[ ! -e $XDG_CONFIG_HOME/$RC_FILE_NAME ]] || fail "wrote the config for a bad combo"
  run "$CA" shortcut frobnicate
  expect "$RC" 1 "unknown action"
  contains "$ERR" "Usage: cachyos-agent shortcut" "usage"
  ok
fi
cleanup_sandbox

begin "shortcut set warns when Plasma cannot find the desktop entry"
setup
if ! command -v kwriteconfig6 >/dev/null; then
  skip "kwriteconfig6 is not installed"
else
  run "$CA" shortcut set
  contains "$ERR" "install -Dm644 $REPO_ROOT/desktop/cachyos-agent.desktop" "install hint from a checkout"
  mkdir -p "$XDG_DATA_HOME/applications"
  cp "$REPO_ROOT/desktop/cachyos-agent.desktop" "$XDG_DATA_HOME/applications/"
  run "$CA" shortcut set
  expect "$ERR" "" "no warning once it is installed"
  rm "$XDG_DATA_HOME/applications/cachyos-agent.desktop"
  mkdir -p "$SANDBOX/no-data-dirs/applications"
  cp "$REPO_ROOT/desktop/cachyos-agent.desktop" "$SANDBOX/no-data-dirs/applications/"
  run "$CA" shortcut set
  expect "$ERR" "" "found through XDG_DATA_DIRS"
  ok
fi
cleanup_sandbox

begin "shortcut needs kwriteconfig6 and says which package has it"
setup
mkdir "$SANDBOX/lean"
for tool in "$TOOLS"/*; do
  [[ ${tool##*/} == k*config6 ]] || ln -s "$tool" "$SANDBOX/lean/"
done
PATH=$SANDBOX/stubs:$REPO_ROOT/bin:$SANDBOX/lean
run "$CA" shortcut set
expect "$RC" 1 "exit status"
contains "$ERR" "kwriteconfig6 and kreadconfig6 are needed (package kconfig)" "message"
ok
cleanup_sandbox

# ---- desktop entry, shell functions, pi extension --------------------------

begin "the pi extension registers the Ollama provider only when the launcher asks"
setup
if ! command -v node >/dev/null || (($(node -p 'process.versions.node.split(".")[0]') < 24)); then
  skip "node 24 or newer, which runs TypeScript files, is not installed"
else
  registered=$(CACHYOS_AGENT_LOCAL_MODEL='qwen3:8b' CACHYOS_AGENT_LOCAL_URL='http://127.0.0.1:11434/v1' \
    node --input-type=module -e '
      const { default: extension } = await import(process.argv[1]);
      const calls = [];
      extension({ registerProvider: (id, config) => calls.push({ id, config }) });
      console.log(JSON.stringify(calls));
    ' "$REPO_ROOT/data/pi-ollama.ts" 2>/dev/null)
  jq -e 'length == 1 and .[0].id == "ollama" and .[0].config.baseUrl == "http://127.0.0.1:11434/v1"
         and .[0].config.api == "openai-completions" and (.[0].config.models | map(.id) == ["qwen3:8b"])' \
    <<<"$registered" >/dev/null || fail "unexpected registration: $registered"
  idle=$(node --input-type=module -e '
    const { default: extension } = await import(process.argv[1]);
    let calls = 0;
    extension({ registerProvider: () => calls++ });
    console.log(calls);
  ' "$REPO_ROOT/data/pi-ollama.ts" 2>/dev/null)
  expect "$idle" 0 "no registration without the launcher's environment"
  ok
fi
cleanup_sandbox

begin "the desktop entry names the app and launches the picker"
setup
entry=$REPO_ROOT/desktop/cachyos-agent.desktop
for line in "Type=Application" "Name=CachyOS Agent" "Exec=cachyos-agent launch --pick" "Icon=utilities-terminal" "Terminal=false" "Categories=Development;"; do
  grep -qxF "$line" "$entry" || fail "desktop entry lacks $line"
done
grep -q '^Comment=.' "$entry" || fail "desktop entry has no Comment"
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$entry" || fail "desktop-file-validate rejects the entry"
fi
ok
cleanup_sandbox

begin "shell functions run what the launcher runs (bash)"
setup
stub_agents opencode claude codex
bash -n "$REPO_ROOT/shell/cachyos-agent.bash" || fail "bash syntax"
for pair in "c:opencode" "cx:claude" "cy:codex"; do
  IFS=: read -r fn agent <<<"$pair"
  CACHYOS_AGENT_DEFAULT=$agent run "$CA" launch --inline
  flags=$(last_call "$agent")
  rm -f "$SANDBOX/calls/$agent"
  bash -c 'source "$1"; shift; "$@"' _ "$REPO_ROOT/shell/cachyos-agent.bash" "$fn" hello "two words" </dev/null 2>/dev/null
  expect "$(last_call "$agent")" "$flags|hello|two words" "$fn adds its arguments to the launcher's flags"
done
CACHYOS_AGENT_DEFAULT=claude bash -c 'source "$1"; a --prompt "via a"' _ "$REPO_ROOT/shell/cachyos-agent.bash" </dev/null
expect "$(last_call claude)" "--permission-mode|auto|--|via a" "a launches the default agent inline"
ok
cleanup_sandbox

begin "shell functions run what the launcher runs (fish)"
setup
if ! command -v fish >/dev/null; then
  skip "fish is not installed"
else
  stub_agents opencode claude codex
  fish --no-config -n "$REPO_ROOT/shell/cachyos-agent.fish" || fail "fish syntax"
  fish --no-config -c 'source $argv[1]; c --prompt one; cx two three; cy -- four' "$REPO_ROOT/shell/cachyos-agent.fish" </dev/null
  expect "$(last_call opencode)" "--auto|--prompt|one" "c"
  expect "$(last_call claude)" "--permission-mode|auto|two|three" "cx"
  expect "$(last_call codex)" "--approve-for-me|--|four" "cy"
  CACHYOS_AGENT_DEFAULT=claude fish --no-config -c 'source $argv[1]; a --prompt "via a"' "$REPO_ROOT/shell/cachyos-agent.fish" </dev/null
  expect "$(last_call claude)" "--permission-mode|auto|--|via a" "a"
  ok
fi
cleanup_sandbox

# ---- the dispatcher ---------------------------------------------------------

begin "the dispatcher lists the launcher commands and answers --help for each"
setup
commands=$("$CA" commands --json)
for route in "cachyos-agent default" "cachyos-agent launch" "cachyos-agent prompt" "cachyos-agent install" "cachyos-agent shortcut"; do
  jq -e --arg route "$route" '.commands | map(.route) | index($route) != null' <<<"$commands" >/dev/null || fail "$route is not listed"
  group=${route#cachyos-agent }
  run "$CA" "$group" --help
  [[ $RC == 0 && $OUT == *Usage:* ]] || fail "$route --help: rc $RC, [$OUT]"
done
"$CA" commands --check >/dev/null || fail "commands --check"
ok
cleanup_sandbox

