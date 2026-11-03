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
  script kwriteconfig6 kreadconfig6 desktop-file-validate fish node; do
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
lacks() { [[ $1 != *"$2"* ]] || fail "$3: [$1] contains [$2]"; }

skip() { printf 'skip %s (%s)\n' "$CURRENT_TEST" "$1"; }

# stub_agents <name...>: stubs that only record their argv.
stub_agents() {
  local name
  for name; do stub "$name"; done
}

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

