#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Adapted from Omarchy bin/omarchy-toggle, omarchy-cmd-present and omarchy-notification-send (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
# Shared helpers for every cachyos-agent command. Source it from a script that
# is a real file under bin/ (it never runs on its own):
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"
# The caller sets its own shell options (set -euo pipefail).

# The data root is the directory above lib/: the repository in a checkout,
# /usr/share/cachyos-agent when packaged. readlink -f lets scripts run through
# the /usr/bin symlinks and still find their own files.
CACHYOS_AGENT_ROOT=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
CACHYOS_AGENT_CONFIG_DIR=${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}/cachyos-agent
CACHYOS_AGENT_STATE_DIR=${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}/cachyos-agent
export CACHYOS_AGENT_ROOT CACHYOS_AGENT_CONFIG_DIR CACHYOS_AGENT_STATE_DIR

# ca_die "message": print to stderr, exit 1.
ca_die() {
  printf '%s: %s\n' "${0##*/}" "$*" >&2
  exit 1
}

# ca_cmd_present cmd...: succeed when every command is an executable on PATH.
# type -P ignores shell functions and aliases, so a stub on PATH is what counts.
ca_cmd_present() {
  local cmd
  for cmd; do
    type -P -- "$cmd" >/dev/null || return 1
  done
}

# ca_version: print the package version.
ca_version() {
  local file=$CACHYOS_AGENT_ROOT/VERSION
  [[ -r $file ]] || ca_die "cannot read $file"
  printf '%s\n' "$(<"$file")"
}

# ca_notify [-u low|normal|critical] [-i icon] [--] summary [body]
# Desktop notification through notify-send when it and a session bus exist,
# otherwise a line on stderr, so callers never need to care. Omarchy sends over
# busctl; notify-send is enough here because summary and body follow `--`: text
# that arrives from a crashed process or a model can start with a dash and must
# never be read as an option (or as a --hint). Put `--` first when the summary
# itself comes from outside.
ca_notify() {
  local -a flags=(--app-name=cachyos-agent)
  while [[ ${1-} == -u || ${1-} == -i ]]; do
    flags+=("$1" "${2:?ca_notify: $1 needs a value}")
    shift 2
  done
  if [[ ${1-} == -- ]]; then
    shift
  fi
  local summary=${1:?ca_notify: summary required} body=${2-}

  if ca_cmd_present notify-send &&
    [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} || -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]] &&
    notify-send "${flags[@]}" -- "$summary" ${body:+"$body"}; then
    return 0
  fi
  printf '%s%s\n' "$summary" "${body:+: $body}" >&2
}

# ca_flag <name> on|off|toggle and ca_flag_enabled <name>: boolean switches kept
# as empty files in $CACHYOS_AGENT_STATE_DIR/toggles. A name is one component or
# two (crash-ignore/firefox), so a caller cannot reach outside that directory.
_ca_flag_path() {
  local part='[[:alnum:]_][[:alnum:]_. -]*'
  [[ $1 =~ ^$part(/$part)?$ ]] || ca_die "invalid flag name: $1"
  _CA_FLAG_PATH=$CACHYOS_AGENT_STATE_DIR/toggles/$1
}

ca_flag_enabled() {
  _ca_flag_path "$1"
  [[ -f $_CA_FLAG_PATH ]]
}

ca_flag() {
  _ca_flag_path "$1"
  case ${2-} in
    on)
      mkdir -p -- "${_CA_FLAG_PATH%/*}"
      : >"$_CA_FLAG_PATH"
      ;;
    off) rm -f -- "$_CA_FLAG_PATH" ;;
    toggle)
      if [[ -f $_CA_FLAG_PATH ]]; then
        ca_flag "$1" off
      else
        ca_flag "$1" on
      fi
      ;;
    *) ca_die "usage: ca_flag <name> on|off|toggle" ;;
  esac
}

# ca_terminal_exec [--title <title>] cmd args...
# Replace this process with `cmd args...` in a new terminal window. Tries
# $TERMINAL, then konsole, alacritty, kitty, foot, ghostty, xterm. The command
# is always passed as separate argv words, never one string, so no shell parses
# it a second time. Each terminal gets its own documented way to run a command:
# -e for konsole, alacritty, ghostty and xterm, plain positional words for
# kitty and foot. An unknown $TERMINAL is assumed to take -e like xterm does,
# and gets no title because there is no portable flag for one.
ca_terminal_exec() {
  local title='' term='' candidate
  local -a prefix=()
  if [[ ${1-} == --title ]]; then
    title=${2:?ca_terminal_exec: --title needs a value}
    shift 2
  fi
  (( $# > 0 )) || ca_die "ca_terminal_exec: no command given"

  for candidate in "${TERMINAL:-}" konsole alacritty kitty foot ghostty xterm; do
    if [[ -n $candidate ]] && ca_cmd_present "$candidate"; then
      term=$candidate
      break
    fi
  done
  [[ -n $term ]] || ca_die "no terminal found; set TERMINAL or install konsole or alacritty"

  case ${term##*/} in
    konsole)
      [[ -z $title ]] || prefix+=(-p "tabtitle=$title")
      prefix+=(-e)
      ;;
    alacritty | xterm)
      [[ -z $title ]] || prefix+=(-T "$title")
      prefix+=(-e)
      ;;
    kitty | foot)
      [[ -z $title ]] || prefix+=(--title "$title")
      ;;
    ghostty)
      [[ -z $title ]] || prefix+=("--title=$title")
      prefix+=(-e)
      ;;
    *) prefix+=(-e) ;;
  esac
  exec "$term" "${prefix[@]}" "$@"
}

# ca_atomic_write <path>: read stdin into <path> without ever leaving a partial
# file there. The temp file sits in the same directory so mv is a rename. The
# result is mode 0600 (mktemp's), which suits state and credentials-adjacent
# files alike.
ca_atomic_write() {
  local path=$1 tmp
  mkdir -p -- "$(dirname -- "$path")"
  tmp=$(mktemp -- "$path.XXXXXX")
  if cat >"$tmp"; then
    mv -f -- "$tmp" "$path"
  else
    rm -f -- "$tmp"
    return 1
  fi
}

# ca_syntax_ok <file>: quietly check a command file's syntax, with py_compile
# for Python scripts and bash -n for everything else. py_compile would write
# __pycache__ next to the script (read-only under /usr/share), so its bytecode
# goes to a throwaway directory.
ca_syntax_ok() {
  local file=$1 first cache ok=0
  IFS= read -r first <"$file" || true
  if [[ $first == '#!'*python* ]]; then
    cache=$(mktemp -d)
    PYTHONPYCACHEPREFIX=$cache python3 -m py_compile "$file" 2>/dev/null || ok=1
    rm -rf -- "$cache"
    return "$ok"
  fi
  bash -n "$file" 2>/dev/null
}
