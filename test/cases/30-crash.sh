#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Crash diagnosis: the diagnose-crash skill, the diagnosis prompt, per-program
# mutes, the journal watcher, and the capture switch with its user unit.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
SKILL_DIR=$REPO_ROOT/agents/skills/diagnose-crash

# ---- the skill files ----------------------------------------------------------

begin "the diagnose-crash skill is complete, indexed, attributed, and names where to report"
make_sandbox
"$AGENT" skills validate >/dev/null || fail "the skill tree does not validate"
grep -qx 'name: diagnose-crash' "$SKILL_DIR/SKILL.md" || fail "frontmatter name is not diagnose-crash"
for topic in SKILL.md reporting.md; do
  grep -qF "(agents/skills/diagnose-crash/$topic)" "$REPO_ROOT/AGENTS.md" || fail "AGENTS.md does not index $topic"
done
grep -qF '(reporting.md)' "$SKILL_DIR/SKILL.md" || fail "SKILL.md does not link reporting.md"
for file in SKILL.md reporting.md; do
  [[ $(grep -ci omarchy "$SKILL_DIR/$file") == 1 ]] || fail "$file should name Omarchy once, in its attribution"
  grep -i omarchy "$SKILL_DIR/$file" | grep -q 'Adapted from the diagnose-crash skill in Omarchy (MIT' || fail "$file has no attribution line naming Omarchy and the MIT licence"
  if grep -qiE 'hyprland|quickshell|omarchy-|\bmise\b' "$SKILL_DIR/$file"; then fail "$file still carries Omarchy-specific content"; fi
done
for url in https://github.com/CachyOS/distribution/issues https://discuss.cachyos.org/c/feedback/bugreports/10 https://github.com/keiranhaax/CachyOS-Agent/issues; do
  grep -qF "$url" "$SKILL_DIR/reporting.md" || fail "reporting.md does not name $url"
done
ok
cleanup_sandbox
