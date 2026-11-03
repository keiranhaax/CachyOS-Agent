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
