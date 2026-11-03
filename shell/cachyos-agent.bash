# SPDX-License-Identifier: GPL-3.0-only
# shellcheck shell=bash
# Short names for the agents, opt-in: add this line to ~/.bashrc
#   source /usr/share/cachyos-agent/shell/cachyos-agent.bash
# Each one runs in the current terminal, in the agent's own don't-stop-to-ask
# mode, with the flags `cachyos-agent launch` uses (see `cachyos-agent launch
# --help`). Arguments are passed through.

a() { cachyos-agent launch --inline "$@"; } # the default agent
c() { opencode --auto "$@"; }               # OpenCode
cx() { claude --permission-mode auto "$@"; } # Claude Code
cy() { codex --approve-for-me "$@"; }        # Codex
