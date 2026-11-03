#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The documentation against the code it describes: a command a document shows
# exists, and the lists a document repeats from the code still match it. The
# prose is not checked, only what a reader would copy or rely on.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
cd "$REPO_ROOT"

# Every document that shows commands or repeats a list from the code.
DOCS=(README.md AGENTS.md MAINTENANCE.md packaging/README.md cachyos-agent.install agents/skills/*/*.md)

begin "every cachyos-agent command in the documents resolves to a command"
make_sandbox
routes=$("$AGENT" commands --json --all | jq -r '.commands[] | .route | ltrimstr("cachyos-agent ")')
declare -A is_route=() is_group=([commands]=1 [version]=1)
while IFS= read -r route; do
  is_route[$route]=1
  is_group[${route%% *}]=1
done <<<"$routes"
unresolved=()
for doc in "${DOCS[@]}"; do
  # Only what is quoted or starts a line counts: a sentence may say
  # "cachyos-agent runtime", a code span or a command line may not.
  while IFS= read -r mention; do
    read -ra words <<<"${mention#*cachyos-agent }"
    group=${words[0]-}
    [[ -n $group ]] || continue
    [[ -n ${is_group[$group]-} ]] || { unresolved+=("$doc: $mention"); continue; }
    # A group of subcommands alone is its help; given more words, one must be a subcommand.
    [[ -n ${is_route[$group]-} || ${#words[@]} -eq 1 ]] && continue
    [[ -n ${words[1]-} && -n ${is_route["$group ${words[1]}"]-} ]] || unresolved+=("$doc: $mention")
  done < <(grep -ohE "(^|[\`\"'])[[:space:]]*cachyos-agent( [a-z][a-z0-9-]*)+" "$doc" || true)
done
if ((${#unresolved[@]} > 0)); then
  fail "no such command: $(printf '%s; ' "${unresolved[@]}")"
fi
ok
cleanup_sandbox

begin "THIRD_PARTY_NOTICES.md lists every file that carries an Omarchy header, with its origin"
# A header reads "Adapted from Omarchy <origin> (MIT, Copyright ...". The notices
# list each file as a table row, | `path` | origin |.
declare -A origin_of=()
# shellcheck disable=SC2016 # the backticks are literal characters of the table row
while IFS=$'\t' read -r path origin; do
  origin_of[$path]=$origin
done < <(sed -nE 's/^\| `([^`]+)` \| (.*) \|$/\1\t\2/p' THIRD_PARTY_NOTICES.md)
((${#origin_of[@]} > 0)) || fail "THIRD_PARTY_NOTICES.md has no file table"
for path in "${!origin_of[@]}"; do
  [[ -f $path ]] || fail "THIRD_PARTY_NOTICES.md lists $path, which does not exist"
done
while IFS=$'\t' read -r path origin; do
  [[ ${origin_of[$path]-} == "$origin" ]] \
    || fail "$path comes from '$origin' but THIRD_PARTY_NOTICES.md says '${origin_of[$path]-not listed}'"
done < <(grep -rE -m1 --exclude-dir=__pycache__ 'Adapted from Omarchy ' bin lib systemd data plasmoid agents shell desktop |
  sed -E 's/^([^:]+):[^A]*Adapted from Omarchy (.*) \(MIT, Copyright.*$/\1\t\2/')
ok

begin "the README command table is what cachyos-agent commands lists"
# The table rows are generated; MAINTENANCE.md gives the command that prints them.
make_sandbox
mapfile -t want < <("$AGENT" commands --json | jq -r '.commands[] | "| `\(.route)` | \(.summary) |"')
mapfile -t have < <(grep -E '^\| `cachyos-agent ' README.md || true)
((${#want[@]} > 0)) || fail "cachyos-agent commands lists nothing"
if [[ ${want[*]} != "${have[*]}" ]]; then
  diff <(printf '%s\n' "${want[@]}") <(printf '%s\n' "${have[@]}") >&2 || true
  fail "the table in README.md differs from the output of cachyos-agent commands (diff above: < is the output)"
fi
ok
cleanup_sandbox

begin "the README agent table matches the launcher and the installer"
# One row per agent id, in the launcher's order. Each flag in a code span must be
# in the launcher's source, and each package in the installer's table under the
# same method, so a flag or package changed in the code cannot stay in the table.
tick=$'\x60'
source "$REPO_ROOT/lib/launcher.sh"
mapfile -t rows < <(awk '/^\| Id \| Agent \|/ { on = 1; next } on && /^\|---/ { next } on && /^\|/ { print; next } on { exit }' README.md)
((${#rows[@]} == ${#CA_AGENT_IDS[@]})) \
  || fail "the agent table has ${#rows[@]} rows for ${#CA_AGENT_IDS[@]} agents"
for i in "${!rows[@]}"; do
  IFS='|' read -r _ id _ install flags _ <<<"${rows[i]}"
  id=${id//[ $tick]/}
  [[ $id == "${CA_AGENT_IDS[i]-}" ]] || { fail "row $((i + 1)) is $id, the launcher's agent $((i + 1)) is ${CA_AGENT_IDS[i]-none}"; continue; }
  package=$(grep -oE "${tick}[^${tick}]+${tick}" <<<"$install" | tr -d "$tick" || true)
  case $install in
    *pacman*) grep -qF "$id) METHOD=repo PACKAGE=$package ;;" bin/cachyos-agent-install || fail "$id: the installer does not install $package with pacman" ;;
    *AUR*) grep -qF "$id) METHOD=aur PACKAGE=$package ;;" bin/cachyos-agent-install || fail "$id: the installer does not install $package from the AUR" ;;
    *vendor*) grep -qF "$id) METHOD=vendor" bin/cachyos-agent-install || fail "$id: the installer does not leave it to the vendor" ;;
    *) fail "$id: the install column says neither pacman, AUR nor vendor" ;;
  esac
  while IFS= read -r flag; do
    # Whole words, so a table that says --yol is not satisfied by --yolo.
    [[ -z $flag ]] || grep -qE -- "(^|[^[:alnum:]-])$flag([^[:alnum:]-]|$)" bin/cachyos-agent-launch || fail "$id: the launcher never uses '$flag'"
  done < <(grep -oE "${tick}[^${tick}]+${tick}" <<<"$flags" | tr -d "$tick" || true)
done
ok

begin "every #anchor link in the documents points at a heading"
# GitHub's slug for a heading: lowercase, anything but letters, digits, spaces,
# '-' and '_' dropped, spaces turned into '-'. Headings and links inside a code
# block do not count.
for doc in "${DOCS[@]}"; do
  [[ $doc == *.md ]] || continue
  mapfile -t slugs < <(awk '/^```/ { fence = !fence; next } !fence && /^#+ / { sub(/^#+ +/, ""); print }' "$doc" |
    tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g')
  while IFS= read -r anchor; do
    [[ " ${slugs[*]} " == *" $anchor "* ]] || fail "$doc links to #$anchor, which is not a heading"
  done < <(awk '/^```/ { fence = !fence; next } !fence' "$doc" | grep -oE '\]\(#[^)]+\)' | sed -E 's/^\]\(#//; s/\)$//' || true)
done
ok
