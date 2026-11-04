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
# Commands call their siblings by bare name (cachyos-agent-launch), never by
# path, so a test stub first on PATH stands in for a sibling and the installed
# /usr/bin copies are what a packaged command runs. The data root's bin is
# appended as the fallback that lets a checkout run before it is installed;
# when an older package is also installed, put the checkout first yourself:
#   PATH=$PWD/bin:$PATH ./bin/cachyos-agent ...
CACHYOS_AGENT_BIN=$CACHYOS_AGENT_ROOT/bin
case ":$PATH:" in
  *":$CACHYOS_AGENT_BIN:"*) ;;
  *) PATH=$PATH:$CACHYOS_AGENT_BIN ;;
esac
export PATH
CACHYOS_AGENT_CONFIG_DIR=${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}/cachyos-agent
CACHYOS_AGENT_STATE_DIR=${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}/cachyos-agent
export CACHYOS_AGENT_ROOT CACHYOS_AGENT_BIN CACHYOS_AGENT_CONFIG_DIR CACHYOS_AGENT_STATE_DIR

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
# two (crash-ignore/firefox). Only what could escape that directory is refused:
# an empty component, a '.' or '..' component, a third level. The name of a
# process is arbitrary text (c++, (sd-pam), .kwin-wrapped) and must still work,
# so a caller building a name from one replaces '/' first (${comm//\//_}).
# ca_flag_enabled is a question and answers false for a name that can never be
# a flag; only ca_flag, which writes, dies on it.
_ca_flag_path() {
  local part='[^/]+'
  [[ $1 =~ ^$part(/$part)?$ ]] || return 1
  case /$1/ in */./* | */../*) return 1 ;; esac
  _CA_FLAG_PATH=$CACHYOS_AGENT_STATE_DIR/toggles/$1
}

ca_flag_enabled() {
  _ca_flag_path "$1" && [[ -f $_CA_FLAG_PATH ]]
}

ca_flag() {
  _ca_flag_path "$1" || ca_die "invalid flag name: $1"
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

# ca_terminal_find
# Print the terminal ca_terminal_exec would use: $TERMINAL, then konsole,
# alacritty, kitty, foot, ghostty, xterm. Fails when none is installed, which a
# caller that has no one watching its stderr can check first and say in a
# notification.
ca_terminal_find() {
  local candidate
  for candidate in "${TERMINAL:-}" konsole alacritty kitty foot ghostty xterm; do
    if [[ -n $candidate ]] && ca_cmd_present "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# ca_terminal_exec [--title <title>] cmd args...
# Replace this process with `cmd args...` in a new terminal window, in the
# terminal ca_terminal_find names. The command
# is always passed as separate argv words, never one string, so no shell parses
# it a second time. Each terminal gets its own documented way to run a command:
# -e for konsole, alacritty, ghostty and xterm, plain positional words for
# kitty and foot. An unknown $TERMINAL is assumed to take -e like xterm does,
# and gets no title because there is no portable flag for one.
ca_terminal_exec() {
  local title='' term=''
  local -a prefix=()
  if [[ ${1-} == --title ]]; then
    title=${2:?ca_terminal_exec: --title needs a value}
    shift 2
  fi
  (( $# > 0 )) || ca_die "ca_terminal_exec: no command given"

  term=$(ca_terminal_find) || ca_die "no terminal found; set TERMINAL or install konsole or alacritty"

  case ${term##*/} in
    konsole)
      # -p reads key=value;key=value and a tab title expands % codes, so a ; or
      # % in a title built from outside text (a process name) would cut the
      # title short or set another profile property. Both become spaces.
      [[ -z $title ]] || prefix+=(-p "tabtitle=${title//[;%]/ }")
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

# ca_atomic_write <path>: replace <path> with stdin by renaming a temp file from
# the same directory over it, so a reader sees the old file or the new one.
# stdin must be the complete content: this function cannot see whether the
# producer of a pipe succeeded, so `producer | ca_atomic_write f` would publish
# half of a crashed producer's output. Capture first and write only on success:
#   data=$(producer) && printf '%s\n' "$data" | ca_atomic_write f
# Empty input is refused for the same reason (a producer that died before it
# printed anything), and the previous file stays. A symlinked <path> is written
# through, so a dotfiles link survives. The result is mode 0600 (mktemp's),
# which suits state and credentials-adjacent files alike. The temp file is
# removed when the write fails or the process is terminated; the subshell keeps
# that cleanup trap from replacing the caller's own.
ca_atomic_write() {
  local path
  path=$(readlink -m -- "${1:?ca_atomic_write: path required}")
  mkdir -p -- "$(dirname -- "$path")"
  (
    tmp=$(mktemp -- "$path.XXXXXX") || exit 1
    trap 'rm -f -- "$tmp"' EXIT
    cat >"$tmp" || exit 1
    if [[ ! -s $tmp ]]; then
      printf '%s: refusing to replace %s with empty input\n' "${0##*/}" "$path" >&2
      exit 1
    fi
    mv -f -- "$tmp" "$path"
  )
}

# ca_syntax_ok <file>: quietly check a source file's syntax, with py_compile
# for Python (a .py name or a python shebang) and bash -n for everything else.
# py_compile would write __pycache__ next to the file (read-only under
# /usr/share), so its bytecode goes to a throwaway directory. -I keeps the
# current directory off sys.path, where -m would otherwise look first: a
# py_compile.py in a directory the command is run from (a checkout just
# downloaded) must not run in its place. -I also ignores PYTHONPYCACHEPREFIX,
# hence -X pycache_prefix.
ca_syntax_ok() {
  local file=$1 first cache ok=0
  IFS= read -r first <"$file" || true
  if [[ $file == *.py || $first == '#!'*python* ]]; then
    cache=$(mktemp -d)
    python3 -I -X pycache_prefix="$cache" -m py_compile "$file" 2>/dev/null || ok=1
    rm -rf -- "$cache"
    return "$ok"
  fi
  bash -n "$file" 2>/dev/null
}
