#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Helpers shared by every test case. A case sources this first:
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"
# then calls begin, make_sandbox, its assertions, ok, cleanup_sandbox and
# finally finish. test/run-tests runs each case in its own bash process.
#
# Cases never touch the real HOME, the network, a display, root or a real agent
# CLI: make_sandbox points every user directory into a temp dir, and stub
# stands in for any external command.

set -Eeuo pipefail

REPO_ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd -P)
export REPO_ROOT
BASE_PATH=$PATH
SANDBOX=''
SANDBOXES=()
CURRENT_TEST=''
TEST_FAILED=0
FAILURES=0

# An unexpected failing command aborts the case; say where, then let it exit.
trap 'printf "FAIL %s: line %s: %s\n" "$CURRENT_TEST" "$LINENO" "$BASH_COMMAND" >&2' ERR
trap 'rm -rf -- "${SANDBOXES[@]}"' EXIT

# begin "name": start a test. ok prints its result unless fail was called.
begin() {
  CURRENT_TEST=$1
  TEST_FAILED=0
}

fail() {
  printf 'FAIL %s: %s\n' "$CURRENT_TEST" "$1" >&2
  TEST_FAILED=1
  FAILURES=$((FAILURES + 1))
}

ok() {
  if ((TEST_FAILED == 0)); then
    printf 'ok   %s\n' "$CURRENT_TEST"
  fi
}

# make_sandbox: a fresh temp dir in $SANDBOX holding HOME and the XDG dirs, a
# stubs/ dir placed first on PATH, and calls/ where stubs record their argv.
# Variables that would leak the real user's agents or terminal into a test are
# cleared, and the session bus is hidden so notifications cannot reach a desktop.
make_sandbox() {
  SANDBOX=$(cd "$(mktemp -d)" && pwd -P) # canonical, so paths compare equal to readlink -f
  SANDBOXES+=("$SANDBOX")
  mkdir -p "$SANDBOX"/{home,run,stubs,calls}
  export HOME=$SANDBOX/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_STATE_HOME=$HOME/.local/state
  export XDG_CACHE_HOME=$HOME/.cache
  export XDG_RUNTIME_DIR=$SANDBOX/run
  unset HERMES_HOME CLAUDE_CONFIG_DIR CODEX_HOME GROK_HOME TERMINAL \
    CACHYOS_AGENT_DEFAULT DBUS_SESSION_BUS_ADDRESS
  PATH=$SANDBOX/stubs:$BASE_PATH
}

# stub <cmd> [body]: an executable <cmd> first on PATH. Each call appends its
# arguments, one per line and followed by a blank line, to $SANDBOX/calls/<cmd>,
# then runs body, a bash snippet that may use "$@". The recording step uses only
# builtins, so stubs still work when a test narrows PATH to the stubs directory.
stub() {
  local cmd=$1 body=${2-}
  cat >"$SANDBOX/stubs/$cmd" <<'EOF'
#!/bin/bash
self=${BASH_SOURCE[0]}
{ for _arg in "$@"; do printf '%s\n' "$_arg"; done; printf '\n'; } >>"${self%/stubs/*}/calls/${self##*/}"
EOF
  printf '%s\n' "$body" >>"$SANDBOX/stubs/$cmd"
  chmod +x "$SANDBOX/stubs/$cmd"
  hash -r # a command this shell already ran stays cached at its old path otherwise
}

# cleanup_sandbox: remove the current sandbox and restore PATH. Sandboxes a case
# forgot are removed when it exits.
cleanup_sandbox() {
  rm -rf -- "$SANDBOX"
  SANDBOX=''
  PATH=$BASE_PATH
}

# finish: end of a case. Exits nonzero when any test failed.
finish() {
  if ((FAILURES > 0)); then
    printf '%d failure(s)\n' "$FAILURES" >&2
    exit 1
  fi
  exit 0
}
