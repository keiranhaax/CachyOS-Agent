# SPDX-License-Identifier: GPL-3.0-only
# shellcheck shell=bash
# Short names for the agents, opt-in: add this line to ~/.bashrc
#   source /usr/share/cachyos-agent/shell/cachyos-agent.bash
# Each one runs in the current terminal, in the agent's own don't-stop-to-ask
# mode, with the flags `cachyos-agent launch` uses (see `cachyos-agent launch
# --help`). Arguments are passed through. Claude Code and Codex go through
# `cachyos-agent account exec`, so they follow `cachyos-agent account use`.

a() { cachyos-agent launch --inline "$@"; }                             # the default agent
c() { opencode --auto "$@"; }                                           # OpenCode
cx() { cachyos-agent account exec claude --permission-mode auto "$@"; } # Claude Code
cy() { cachyos-agent account exec codex --approve-for-me "$@"; }        # Codex
