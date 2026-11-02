#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# test/lib.sh itself: what make_sandbox keeps out of a case, and that a case's
# exit status follows its assertions without any call at the end.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

# run_case <snippet>: run a throwaway case that sources test/lib.sh and then
# <snippet> in its own bash, the way test/run-tests runs a real one. Returns
# the case's exit status.
run_case() {
  printf 'source "%s/test/lib.sh"\n%s\n' "$REPO_ROOT" "$1" >"$SANDBOX/case.sh"
  bash "$SANDBOX/case.sh" >/dev/null 2>&1
}

begin "make_sandbox clears what would leak the caller's environment into a case"
leaky=(CACHYOS_SKILLS_SRC CACHYOS_AGENT_DEFAULT TERMINAL HERMES_HOME CLAUDE_CONFIG_DIR CODEX_HOME GROK_HOME DBUS_SESSION_BUS_ADDRESS)
for var in "${leaky[@]}"; do export "$var=/leaked"; done
make_sandbox
for var in "${leaky[@]}"; do
  [[ -z ${!var+set} ]] || fail "$var survived make_sandbox"
done
[[ $HOME == "$SANDBOX/home" && $XDG_STATE_HOME == "$SANDBOX/home/.local/state" ]] || fail "HOME or XDG_STATE_HOME is outside the sandbox"
ok
cleanup_sandbox

begin "a case exits nonzero after a failed assertion, with nothing to call at the end"
make_sandbox
if run_case 'begin "deliberate"; make_sandbox; [[ 1 == 2 ]] || fail "must fail"; ok; cleanup_sandbox'; then
  fail "a case that called fail exited 0"
fi
if run_case 'begin "deliberate"; make_sandbox; fail "first"; fail "second"'; then
  fail "a case that never cleaned up and called fail exited 0"
fi
ok
cleanup_sandbox

begin "a case exits 0 when every assertion held and nonzero when a command aborted it"
make_sandbox
run_case 'begin "fine"; make_sandbox; [[ 1 == 1 ]] || fail "unreachable"; ok; cleanup_sandbox' \
  || fail "a clean case exited nonzero"
if run_case 'begin "aborts"; make_sandbox; false; ok'; then
  fail "a case with an unexpected failing command exited 0"
fi
ok
cleanup_sandbox
