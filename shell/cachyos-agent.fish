# SPDX-License-Identifier: GPL-3.0-only
# Short names for the agents, opt-in: add this line to ~/.config/fish/config.fish
#   source /usr/share/cachyos-agent/shell/cachyos-agent.fish
# Each one runs in the current terminal, in the agent's own don't-stop-to-ask
# mode, with the flags `cachyos-agent launch` uses (see `cachyos-agent launch
# --help`). Arguments are passed through.

function a --description 'Launch the default coding agent here'
    cachyos-agent launch --inline $argv
end

function c --description 'OpenCode in auto mode'
    opencode --auto $argv
end

function cx --description 'Claude Code in auto mode'
    claude --permission-mode auto $argv
end

function cy --description 'Codex in auto mode'
    codex --approve-for-me $argv
end
