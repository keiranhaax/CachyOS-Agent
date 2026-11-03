#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Adapted from Omarchy bin/omarchy-default-agent and omarchy-cmd-present (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
# The agent table shared by cachyos-agent-default, -install and -launch. Source
# it after lib/common.sh; it never runs on its own. The ids below are the whole
# list of agents the launcher can start, and ca_agent_resolve is the only place
# that maps a name a user typed to one.

# shellcheck disable=SC2034 # every variable here is read by the scripts that source this file

# In the order the usage text lists them.
CA_AGENT_IDS=(pi omp opencode ori claude codex grok agy hermes copilot crush cursor-agent muse kimi qwen dsh mcode kiro-cli freebuff kilo devin amp commandcode)

# ca_agent_resolve <name>: set CA_AGENT to the agent id and CA_AGENT_NAME to its
# display name, or fail for a name that is not an agent. Accepts the aliases
# people actually type (claude-code, gemini, cursor, ...).
ca_agent_resolve() {
  case ${1-} in
    pi) CA_AGENT=pi CA_AGENT_NAME="Pi" ;;
    omp | oh-my-pi) CA_AGENT=omp CA_AGENT_NAME="Oh My Pi" ;;
    opencode | open-code) CA_AGENT=opencode CA_AGENT_NAME="OpenCode" ;;
    ori | openrouter) CA_AGENT=ori CA_AGENT_NAME="Ori" ;;
    claude | claude-code) CA_AGENT=claude CA_AGENT_NAME="Claude Code" ;;
    codex) CA_AGENT=codex CA_AGENT_NAME="Codex" ;;
    crush) CA_AGENT=crush CA_AGENT_NAME="Crush" ;;
    grok) CA_AGENT=grok CA_AGENT_NAME="Grok" ;;
    agy | antigravity | antigravity-cli | gemini | gemini-cli) CA_AGENT=agy CA_AGENT_NAME="Antigravity" ;;
    hermes) CA_AGENT=hermes CA_AGENT_NAME="Hermes" ;;
    copilot | github-copilot) CA_AGENT=copilot CA_AGENT_NAME="GitHub Copilot" ;;
    muse | muse-code | musecode) CA_AGENT=muse CA_AGENT_NAME="Muse Code" ;;
    cursor | cursor-agent) CA_AGENT=cursor-agent CA_AGENT_NAME="Cursor CLI" ;;
    kimi | kimi-code) CA_AGENT=kimi CA_AGENT_NAME="Kimi" ;;
    qwen | qwen-code) CA_AGENT=qwen CA_AGENT_NAME="Qwen Code" ;;
    dsh | deepseek | deepseek-harness) CA_AGENT=dsh CA_AGENT_NAME="DeepSeek Harness" ;;
    mcode | minimax-code | minimax) CA_AGENT=mcode CA_AGENT_NAME="MiniMax Code" ;;
    kiro-cli | kiro) CA_AGENT=kiro-cli CA_AGENT_NAME="Kiro CLI" ;;
    freebuff) CA_AGENT=freebuff CA_AGENT_NAME="Freebuff" ;;
    kilo | kilocode | kilo-code) CA_AGENT=kilo CA_AGENT_NAME="Kilo" ;;
    devin | devin-cli) CA_AGENT=devin CA_AGENT_NAME="Devin CLI" ;;
    amp | ampcode) CA_AGENT=amp CA_AGENT_NAME="Amp" ;;
    commandcode | command-code | cmdc) CA_AGENT=commandcode CA_AGENT_NAME="Command Code" ;;
    *) return 1 ;;
  esac
}

# ca_agent_binary <id>: print what runs the agent, or fail when nothing does:
# its name when it is on PATH, else the user's own install in ~/.local/bin by
# path, where several vendors' installers put it and which a desktop session
# does not always have on PATH. Every command that starts or asks an agent's
# CLI goes through this, so they agree on which copy that is.
ca_agent_binary() {
  if ca_cmd_present "$1"; then
    printf '%s\n' "$1"
  elif [[ -f ${HOME:?}/.local/bin/$1 && -x $HOME/.local/bin/$1 ]]; then
    printf '%s\n' "$HOME/.local/bin/$1"
  else
    return 1
  fi
}

# ca_agent_present <id>: the agent's CLI is installed, on PATH or in ~/.local/bin.
ca_agent_present() {
  ca_agent_binary "$1" >/dev/null
}

# ca_opencode_major: the major version of the OpenCode that will run, or nothing
# when it is not installed or does not say. OpenCode 1 and 2 differ in what the
# launcher passes it and where it reads its settings, and this is where both ask.
ca_opencode_major() {
  local binary
  binary=$(ca_agent_binary opencode) || return 0
  "$binary" --version 2>/dev/null | grep -oE '[0-9]+' | head -n 1 || true
}
