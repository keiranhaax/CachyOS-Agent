#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The collectors on a machine that uses their agent. 50-usage runs each one on
# an empty machine, where it only has to say "not in use"; here each runs on a
# machine with credentials or session files and a service that answers, so
# its parsing of limits, balances and plans is what the case checks.
# test/usage/<agent>.py describes the machine and the replies, and
# test/usage-fixture.py runs the real collector against it.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

FIXTURES=$REPO_ROOT/test/usage
DRIVER=$REPO_ROOT/test/usage-fixture.py
# The collectors whose in-use path 50-usage runs with a fixture of its own.
COVERED_IN_50_USAGE=(claude hermes local zai agy)

# fixture_run <collector> <fixture>: the driver's verdict, with its message on stderr.
fixture_run() { python3 -I "$DRIVER" "$1" "$2"; }

begin "every collector has a fixture here or a case in 50-usage that runs it on a machine that uses its agent"
for file in "$REPO_ROOT"/bin/cachyos-agent-usage-*; do
  grep -q '^# cachyos-agent:args=\[--force\] \[--limits-only\]$' "$file" || continue
  agent=${file##*cachyos-agent-usage-}
  [[ -f $FIXTURES/$agent.py || " ${COVERED_IN_50_USAGE[*]} " == *" $agent "* ]] || fail "$agent has no test/usage/$agent.py"
done
ok

begin "the fixture driver fails a collector that ignores its machine, one that writes to stderr and one that exits nonzero"
make_sandbox
printf '%s\n' '#!/usr/bin/python3' 'import json' 'def main():' '  print(json.dumps({"id": "deepseek", "ready": False, "limits": []}))' '  return 0' >"$SANDBOX/unused"
printf '%s\n' '#!/usr/bin/python3' 'import sys' 'def main():' '  print("{}")' '  print("a bug", file=sys.stderr)' '  return 0' >"$SANDBOX/noisy"
printf '%s\n' '#!/usr/bin/python3' 'def main():' '  return 3' >"$SANDBOX/failing"
for stand_in in unused noisy failing; do
  if fixture_run "$SANDBOX/$stand_in" "$FIXTURES/deepseek.py" 2>/dev/null; then fail "a collector that is $stand_in passed the deepseek fixture"; fi
done
ok
cleanup_sandbox

for fixture in "$FIXTURES"/*.py; do
  name=$(basename "$fixture" .py)
  agent=${name%%-*}
  begin "the $agent collector reports the machine in test/usage/$name.py"
  make_sandbox
  fixture_run "$REPO_ROOT/bin/cachyos-agent-usage-$agent" "$fixture" 2>"$SANDBOX/err" || fail "$(head -c 1200 "$SANDBOX/err")"
  ok
  cleanup_sandbox
done
