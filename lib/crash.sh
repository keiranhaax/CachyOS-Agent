#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Adapted from Omarchy bin/omarchy-crash-watch and omarchy-crash-mute (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
# What cachyos-agent-crash-watch and cachyos-agent-crash-mute must agree on: the
# name a program is muted under. Source it after lib/common.sh.

# crash_program_name <name-or-path>: print the name a program is muted under, or
# fail when nothing usable is left.
#
# The watcher keys a mute on the executable's basename and falls back to comm,
# which a process can set to anything prctl takes, slashes included. The name
# becomes a path under toggles/crash-ignore/, so it is cut to its last component:
# a crash must not reach a flag outside that directory, nor a mute write one.
# What remains is still not always a name. "/" leaves nothing, and a dot
# component names a directory rather than a flag, so a mute on it would touch
# that directory and then never match. Control characters become '?' so a name
# can neither forge a line in a listing nor reach a terminal as an escape.
crash_program_name() {
  local name=${1##*/}
  name=${name//[[:cntrl:]]/?}
  [[ -n $name && $name != . && $name != .. ]] || return 1
  printf '%s\n' "$name"
}
