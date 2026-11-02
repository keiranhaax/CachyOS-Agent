#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The theme commands: the template renderer in lib/theme.sh, the Plasma palette,
# the sync into Hermes, Claude Code, Pi and OpenCode, and the follow watcher.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

# render <palette-file>: the template on stdin through theme_render, run the way
# a command runs it (common.sh first), in its own process.
render() {
  bash -c 'source "$1/lib/common.sh"; source "$1/lib/theme.sh"; theme_render "$2"' _ "$REPO_ROOT" "$1"
}

# ---- theme_render ------------------------------------------------------------

begin "theme_render expands keys and mixes colors with exact arithmetic"
make_sandbox
printf '%s\t%s\n' background '#000000' foreground '#ffffff' red '#da4453' theme_type dark >"$SANDBOX/palette"
out=$(render "$SANDBOX/palette" <<'TPL'
bg={{ background }} type={{theme_type}} half={{ mix background foreground 50% }}
quarter={{ mix #000000 #ffffff 0.25 }} bare={{ mix background foreground 25 }} both={{ red }}/{{ mix red foreground 30% }}
none={{ mix red foreground 0% }} all={{ mix red foreground 100% }} over={{ mix red foreground 150% }} up={{ mix #FFFFFF #000000 10% }}
no placeholders here
TPL
)
expected='bg=#000000 type=dark half=#808080
quarter=#404040 bare=#404040 both=#da4453/#e57c87
none=#da4453 all=#ffffff over=#ffffff up=#e6e6e6
no placeholders here'
[[ $out == "$expected" ]] || fail "unexpected render: $out"
ok
cleanup_sandbox

begin "theme_render fails instead of leaving a placeholder behind"
make_sandbox
printf '%s\t%s\n' background '#000000' foreground '#ffffff' theme_type dark >"$SANDBOX/palette"
while IFS='|' read -r template message; do
  if out=$(printf '%s\n' "$template" | render "$SANDBOX/palette" 2>"$SANDBOX/err"); then
    fail "'$template' rendered as: $out"
  fi
  grep -qF -- "$message" "$SANDBOX/err" || fail "'$template' gave: $(<"$SANDBOX/err")"
done <<'CASES'
{{ missing }}|unknown palette key "missing"
{{ mix background missing 10% }}|unknown palette key "missing"
{{ mix background theme_type 10% }}|is not a color
{{ mix background foreground lots }}|bad mix amount
{{ mix background foreground }}|cannot read
{{ }}|cannot read
broken {{ background|unterminated
CASES
if render "$SANDBOX/nope" </dev/null 2>/dev/null; then fail "a missing palette file was accepted"; fi
ok
cleanup_sandbox
