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

# shellcheck source=../doc-commands.sh
source "$REPO_ROOT/test/doc-commands.sh"

# catalog_and_groups: set $catalog (one route and its args metadata per line, tab
# separated) and $groups from the dispatcher, hidden commands included.
catalog_and_groups() {
  local all
  all=$("$AGENT" commands --json --all)
  groups=$(jq -r '.commands | map(.group) | unique[]' <<<"$all"
    printf 'commands\nversion\n')
  catalog=$(jq -r '.commands[] | [(.route | sub("^cachyos-agent "; "")), (.args // "")] | @tsv' <<<"$all"
    printf 'commands\t[--all] [--json] [--check]\nversion\t\n')
}

begin "every cachyos-agent command in the documents is a command the dispatcher has, with an action it takes"
make_sandbox
catalog_and_groups
for doc in "${DOCS[@]}"; do
  bad=$(unknown_commands "$doc" "$catalog" "$groups")
  [[ -z $bad ]] || fail "$doc shows commands or arguments that do not exist: $(tr '\n' ',' <<<"$bad")"
done
ok
cleanup_sandbox

begin "the check of documented commands sees what it is looking for"
make_sandbox
catalog_and_groups
# A command that is no route, and an action a route does not take (local pause, usage
# schedul on), in each form a document shows one, while the words a route does take,
# free ones included, pass.
cat >"$SANDBOX/doc.md" <<'DOC'
Run `cachyos-agent account use work` or `cachyos-agent crash capture on`; the `cachyos-agent` package.

```
$ cachyos-agent usage --json
cachyos-agent theme sync --activate
sudo pacman -S cachyos-agent cachyos-keyring
```

Not commands: `cachyos-agent-launch`, `cachyos-agent package`, `cachyos-agent account switch`, `cachyos-agent frobnicate`.

```
cachyos-agent account switch work
cachyos-agent account
```

Commands that take free arguments, and the actions of those that do not:

```
cachyos-agent local use best
cachyos-agent shortcut set Meta+Ctrl+Shift+A
cachyos-agent default claude
cachyos-agent install claude
cachyos-agent prompt fix the build
cachyos-agent usage update claude codex
cachyos-agent usage claude
cachyos-agent usage schedule on
cachyos-agent crash mute firefox
cachyos-agent account mode auto 90
cachyos-agent launch --pick
cachyos-agent commands --check
```

Not commands, in a block:

```
cachyos-agent local pause
cachyos-agent shortcut remove
cachyos-agent default clude
cachyos-agent usage schedul on
cachyos-agent crash captur on
cachyos-agent theme follow onn
cachyos-agent launch pi
cachyos-agent usage claude codex
cachyos-agent version now
```

Not commands, in prose:

cachyos-agent crash captur now
- cachyos-agent usage schedul off
echo "  cachyos-agent local pauze"
Say 'cachyos-agent default clude' and `cachyos-agent crash mute firefox off`.
DOC
seen=$(doc_commands "$SANDBOX/doc.md" | LC_ALL=C sort -u | tr '\n' ',')
[[ $seen == "account,account mode auto,account switch,account switch work,account use work,commands,crash captur now,crash captur on,crash capture on,crash mute firefox,crash mute firefox off,default claude,default clude,frobnicate,install claude,launch,launch pi,local pause,local pauze,local use best,package,prompt fix the build,shortcut remove,shortcut set,theme follow onn,theme sync,usage,usage claude,usage claude codex,usage schedul off,usage schedul on,usage schedule on,usage update claude codex,version now," ]] \
  || fail "the reader does not see the commands it should: $seen"
bad=$(unknown_commands "$SANDBOX/doc.md" "$catalog" "$groups" | tr '\n' ',')
[[ $bad == "cachyos-agent account switch,cachyos-agent account switch work,cachyos-agent crash captur now,cachyos-agent crash captur on,cachyos-agent default clude,cachyos-agent frobnicate,cachyos-agent launch pi,cachyos-agent local pause,cachyos-agent local pauze,cachyos-agent package,cachyos-agent shortcut remove,cachyos-agent theme follow onn,cachyos-agent usage claude codex,cachyos-agent usage schedul off,cachyos-agent usage schedul on,cachyos-agent version now," ]] \
  || fail "the check does not catch exactly the commands that do not exist: $bad"
ok
cleanup_sandbox

# A header reads "# Adapted from Omarchy <origin> (MIT, Copyright ..." (or after //).
# header_problems <dir...>: what is wrong with the Omarchy headers under those
# directories, one line each: a header that does not have that shape (which would
# otherwise read as an unlisted file with no origin and match another one), a file
# the notices do not list, and a file whose origin differs from the notices'.
header_re='^([^:]+):(#|//)[[:space:]]+Adapted from Omarchy (.+) \(MIT, Copyright'
header_problems() {
  local hit path origin
  while IFS= read -r hit; do
    if [[ $hit =~ $header_re ]]; then
      path=${BASH_REMATCH[1]} origin=${BASH_REMATCH[3]}
      [[ ${origin_of[$path]-} == "$origin" ]] \
        || echo "$path comes from '$origin' but THIRD_PARTY_NOTICES.md says '${origin_of[$path]-not listed}'"
    else
      echo "an Omarchy header of an unexpected shape: $hit"
    fi
  done < <(grep -rE -m1 --exclude-dir=__pycache__ 'Adapted from Omarchy' "$@")
}

begin "THIRD_PARTY_NOTICES.md lists every file that carries an Omarchy header, with its origin"
# The notices list each file as a table row, | `path` | origin |.
declare -A origin_of=()
# shellcheck disable=SC2016 # the backticks are literal characters of the table row
while IFS=$'\t' read -r path origin; do
  origin_of[$path]=$origin
done < <(sed -nE 's/^\| `([^`]+)` \| (.*) \|$/\1\t\2/p' THIRD_PARTY_NOTICES.md)
((${#origin_of[@]} > 0)) || fail "THIRD_PARTY_NOTICES.md has no file table"
for path in "${!origin_of[@]}"; do
  [[ -f $path ]] || fail "THIRD_PARTY_NOTICES.md lists $path, which does not exist"
done
problems=$(header_problems bin lib systemd data plasmoid agents shell desktop)
[[ -z $problems ]] || fail "$(tr '\n' ';' <<<"$problems")"
ok

begin "the check of Omarchy headers refuses a header it cannot read, an unlisted file and a wrong origin"
make_sandbox
listed=${!origin_of[*]}
listed=${listed%% *}
known_origin=${origin_of[$listed]}
mkdir -p "$SANDBOX/tree/lib" "$SANDBOX/tree/${listed%/*}"
header() { printf '%s Adapted from Omarchy %s (MIT, Copyright (c) Someone); see THIRD_PARTY_NOTICES.md\n' "$1" "$2"; }
header '#' "$known_origin" >"$SANDBOX/tree/$listed"
header '#' 'bin/omarchy-wrong' >"$SANDBOX/tree/lib/wrong-origin.sh"
header '#' 'bin/omarchy-foo' >"$SANDBOX/tree/lib/unlisted.sh"
header '//' 'bin/omarchy-foo' >"$SANDBOX/tree/lib/unlisted.js"
# What the old reader took for an empty origin and let through.
echo '# Adapted from Omarchy bin/omarchy-foo (MIT licence, see notices)' >"$SANDBOX/tree/lib/typo.sh"
echo '# A Adapted from Omarchy bin/omarchy-foo (MIT, Copyright (c) Someone)' >"$SANDBOX/tree/lib/stray.sh"
problems=$(cd "$SANDBOX/tree" && header_problems lib "${listed%%/*}" | LC_ALL=C sort -u)
for expected in "lib/wrong-origin.sh comes from 'bin/omarchy-wrong'" "lib/unlisted.sh comes from 'bin/omarchy-foo' but THIRD_PARTY_NOTICES.md says 'not listed'" \
  "lib/unlisted.js comes from" "an Omarchy header of an unexpected shape: lib/typo.sh" "an Omarchy header of an unexpected shape: lib/stray.sh"; do
  [[ $problems == *"$expected"* ]] || fail "the check missed: $expected (it said: $problems)"
done
[[ $problems != *"$listed comes"* && $problems != *"$listed:"* ]] || fail "the check refused the listed file with its own origin: $problems"
ok
cleanup_sandbox

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

begin "the line that reads a command's source works when only the dispatcher is linked"
# README, "Install from a Git checkout", links bin/cachyos-agent alone into a PATH
# directory; the package also links every command into /usr/bin. A document
# that finds a command with `command -v cachyos-agent-<name>` fails in the first
# case, so the line SKILL.md shows is run as written with only the dispatcher
# and four tools on PATH (a package installed on this machine cannot help it).
make_sandbox
mkdir "$SANDBOX/path"
for tool in bash cat dirname readlink; do ln -s "$(command -v "$tool")" "$SANDBOX/path/$tool"; done
ln -s "$AGENT" "$SANDBOX/path/cachyos-agent"
mapfile -t found < <(grep -n 'command -v cachyos-agent-' "${DOCS[@]}" || true)
((${#found[@]} == 0)) || fail "the documents find a command with command -v, which a checkout does not link: $(printf '%s; ' "${found[@]}")"
line=$(grep -m1 -E '^cat ".*cachyos-agent-crash"$' agents/skills/cachyos/SKILL.md || true)
[[ -n $line ]] || fail "SKILL.md shows no line that reads cachyos-agent-crash"
shown=$(PATH=$SANDBOX/path "$SANDBOX/path/bash" -c "$line" 2>&1 || true)
[[ $shown == *'cachyos-agent:summary='* ]] || fail "the line '$line' did not print the command: ${shown:-nothing}"
ok
cleanup_sandbox

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
