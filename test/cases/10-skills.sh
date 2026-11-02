#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The skills commands (provisioner, validator) and the package layout.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
PROVISION=$REPO_ROOT/bin/cachyos-agent-skills-provision
VALIDATE=$REPO_ROOT/bin/cachyos-agent-skills-validate

DEST_PARENTS=(
  .agents/skills
  .claude/skills
  .codex/skills
  .pi/agent/skills
  .gemini/config/skills
  .hermes/skills
)

# make_skill_src: $SRC, a one-skill source tree inside the sandbox.
make_skill_src() {
  SRC=$SANDBOX/src/agents/skills
  mkdir -p "$SRC/cachyos"
  printf -- '---\nname: cachyos\ndescription: test skill\n---\n# body\n' >"$SRC/cachyos/SKILL.md"
}

# make_valid_tree <dir>: the smallest tree the validator accepts.
make_valid_tree() {
  mkdir -p "$1/agents/skills/cachyos" "$1/bin" "$1/lib"
  printf -- '---\nname: cachyos\ndescription: test skill\n---\n# body\n' >"$1/agents/skills/cachyos/SKILL.md"
}

# ---- provisioner -----------------------------------------------------------

begin "provision links all harness paths"
make_sandbox
make_skill_src
"$PROVISION" "$SRC" >/dev/null
for parent in "${DEST_PARENTS[@]}"; do
  link=$HOME/$parent/cachyos
  if [[ ! -L $link ]]; then
    fail "$link is not a symlink"
  elif [[ $(readlink "$link") != "$SRC/cachyos" ]]; then
    fail "$link points at $(readlink "$link")"
  fi
done
ok
cleanup_sandbox

begin "provision is idempotent"
make_sandbox
make_skill_src
"$PROVISION" "$SRC" >/dev/null
"$PROVISION" "$SRC" >/dev/null
[[ -L $HOME/.claude/skills/cachyos ]] || fail "second run broke the link"
ok
cleanup_sandbox

begin "provision honors the Hermes profile home"
make_sandbox
make_skill_src
profile_home=$SANDBOX/hermes-profile
HERMES_HOME=$profile_home "$PROVISION" "$SRC" >/dev/null
link=$profile_home/skills/cachyos
if [[ ! -L $link ]]; then
  fail "$link is not a symlink"
elif [[ $(readlink "$link") != "$SRC/cachyos" ]]; then
  fail "$link points at $(readlink "$link")"
fi
[[ ! -e $HOME/.hermes/skills/cachyos ]] || fail "default Hermes path was linked despite HERMES_HOME"
ok
cleanup_sandbox

begin "provision defaults to the skills under the data root"
make_sandbox
"$PROVISION" >/dev/null
[[ $(readlink "$HOME/.claude/skills/cachyos") == "$REPO_ROOT/agents/skills/cachyos" ]] \
  || fail "default source is not agents/skills under the data root"
ok
cleanup_sandbox

begin "provision skips regular dirs without --force"
make_sandbox
make_skill_src
mkdir -p "$HOME/.claude/skills/cachyos"
if "$PROVISION" "$SRC" >/dev/null 2>&1; then
  fail "expected nonzero exit when a regular directory blocks a dest"
fi
[[ -d $HOME/.claude/skills/cachyos && ! -L $HOME/.claude/skills/cachyos ]] \
  || fail "regular directory was replaced without --force"
ok
cleanup_sandbox

begin "provision --force backs up prior skill dirs"
make_sandbox
make_skill_src
mkdir -p "$HOME/.claude/skills/cachyos"
printf 'old\n' >"$HOME/.claude/skills/cachyos/SKILL.md"
"$PROVISION" --force "$SRC" >/dev/null
[[ -L $HOME/.claude/skills/cachyos ]] || fail "dest was not replaced by a symlink"
backups=("$HOME"/.claude/skills/cachyos.backup.*)
if [[ ! -e ${backups[0]:-} ]]; then
  fail "no timestamped backup was created"
elif [[ $(<"${backups[0]}/SKILL.md") != old ]]; then
  fail "backup does not contain the previous contents"
fi
ok
cleanup_sandbox

begin "provision --force refuses non-skill dirs"
make_sandbox
make_skill_src
mkdir -p "$HOME/.claude/skills/cachyos"
printf 'data\n' >"$HOME/.claude/skills/cachyos/notes.txt"
if "$PROVISION" --force "$SRC" >/dev/null 2>&1; then
  fail "expected refusal for a directory without SKILL.md"
fi
[[ -f $HOME/.claude/skills/cachyos/notes.txt ]] || fail "non-skill directory was modified"
ok
cleanup_sandbox

begin "provision refuses sources without SKILL.md"
make_sandbox
mkdir -p "$SANDBOX/src/agents/skills/broken"
if "$PROVISION" "$SANDBOX/src/agents/skills" >/dev/null 2>&1; then
  fail "expected refusal for a skill directory without SKILL.md"
fi
ok
cleanup_sandbox

begin "cachyos-agent skills provision reaches the provisioner"
make_sandbox
make_skill_src
"$AGENT" skills provision "$SRC" >/dev/null
[[ -L $HOME/.agents/skills/cachyos ]] || fail "no link created through the dispatcher"
ok
cleanup_sandbox

begin "every skills command prints usage for --help"
make_sandbox
for command in provision update check-upstreams validate; do
  if ! out=$("$AGENT" skills "$command" --help 2>&1); then
    fail "skills $command --help exited nonzero"
  elif [[ $out != *"Usage: cachyos-agent skills $command"* ]]; then
    fail "skills $command --help does not show its usage"
  fi
done
ok
cleanup_sandbox

# ---- validator -------------------------------------------------------------

begin "validate accepts the repository tree"
make_sandbox
"$VALIDATE" "$REPO_ROOT" >/dev/null || fail "validator rejected the repository"
ok
cleanup_sandbox

begin "validate rejects broken links and bad frontmatter"
make_sandbox
cp -a "$REPO_ROOT/agents" "$REPO_ROOT/AGENTS.md" "$SANDBOX/"
printf '[gone](missing-topic.md)\n' >>"$SANDBOX/agents/skills/cachyos/kernel.md"
sed -i 's/^name: cachyos$/name: wrong/' "$SANDBOX/agents/skills/cachyos/SKILL.md"
if "$VALIDATE" "$SANDBOX" >/dev/null 2>&1; then
  fail "validator accepted broken links and mismatched frontmatter"
fi
ok
cleanup_sandbox

begin "validate rejects empty frontmatter descriptions"
make_sandbox
for empty_desc in 'description:' 'description: >'; do
  tree=$SANDBOX/tree
  rm -rf "$tree"
  mkdir -p "$tree/agents/skills/cachyos"
  printf -- '---\nname: cachyos\n%s\n---\n# body\n' "$empty_desc" >"$tree/agents/skills/cachyos/SKILL.md"
  if "$VALIDATE" "$tree" >/dev/null 2>&1; then
    fail "validator accepted '$empty_desc' as a description"
  fi
done
ok
cleanup_sandbox

begin "validate accepts folded descriptions with content"
make_sandbox
mkdir -p "$SANDBOX/agents/skills/cachyos"
printf -- '---\nname: cachyos\ndescription: >\n  Real trigger text.\n---\n# body\n' \
  >"$SANDBOX/agents/skills/cachyos/SKILL.md"
"$VALIDATE" "$SANDBOX" >/dev/null 2>&1 || fail "validator rejected a folded description"
ok
cleanup_sandbox

begin "validate checks bin scripts: summary, hidden, syntax"
make_sandbox
tree=$SANDBOX/tree
make_valid_tree "$tree"
printf '#!/bin/bash\n# cachyos-agent:summary=fine\n' >"$tree/bin/cachyos-agent-ok"
printf '#!/bin/bash\n# cachyos-agent:hidden=true\n' >"$tree/bin/cachyos-agent-internal"
chmod +x "$tree"/bin/*
"$VALIDATE" "$tree" >/dev/null 2>&1 || fail "validator rejected a tree with a summary and a hidden command"
printf '#!/bin/bash\n' >"$tree/bin/cachyos-agent-bare"
chmod +x "$tree/bin/cachyos-agent-bare"
if "$VALIDATE" "$tree" >/dev/null 2>&1; then
  fail "validator accepted a bin script without a summary"
fi
rm "$tree/bin/cachyos-agent-bare"
printf '#!/bin/bash\n# cachyos-agent:summary=broken\nif then\n' >"$tree/bin/cachyos-agent-broken"
chmod +x "$tree/bin/cachyos-agent-broken"
if "$VALIDATE" "$tree" >/dev/null 2>&1; then
  fail "validator accepted a bin script with a syntax error"
fi
rm "$tree/bin/cachyos-agent-broken"
printf '#!/bin/bash\n# cachyos-agent:summary=not executable\n' >"$tree/bin/cachyos-agent-plain"
if "$VALIDATE" "$tree" >/dev/null 2>&1; then
  fail "validator accepted a bin script that is not executable"
fi
ok
cleanup_sandbox

begin "validate checks lib/*.sh syntax"
make_sandbox
tree=$SANDBOX/tree
make_valid_tree "$tree"
printf '# shell helpers\nf() { :; }\n' >"$tree/lib/good.sh"
"$VALIDATE" "$tree" >/dev/null 2>&1 || fail "validator rejected a valid lib file"
printf 'if then\n' >"$tree/lib/bad.sh"
if "$VALIDATE" "$tree" >/dev/null 2>&1; then
  fail "validator accepted a lib file with a syntax error"
fi
ok
cleanup_sandbox

begin "validate checks lib/*.py syntax"
make_sandbox
tree=$SANDBOX/tree
make_valid_tree "$tree"
printf 'print("collect")\n' >"$tree/lib/good.py"
"$VALIDATE" "$tree" >/dev/null 2>&1 || fail "validator rejected a valid Python helper"
printf 'def (\n' >"$tree/lib/bad.py"
if "$VALIDATE" "$tree" >/dev/null 2>&1; then
  fail "validator accepted a Python helper with a syntax error"
fi
[[ -z $(find "$tree" -name __pycache__) ]] || fail "py_compile left bytecode in the tree"
ok
cleanup_sandbox

begin "skills commands exit 2, not 1, when ROOT is not a directory"
make_sandbox
touch "$SANDBOX/a-file"
for command in validate check-upstreams update; do
  for root in "$SANDBOX/no-such-dir" "$SANDBOX/a-file"; do
    status=0
    out=$("$AGENT" skills "$command" "$root" 2>&1) || status=$?
    [[ $status -eq 2 ]] || fail "skills $command exited $status for $root"
    [[ $out == *"not a directory: $root"* ]] || fail "skills $command did not name the bad ROOT $root: $out"
  done
done
ok
cleanup_sandbox

# ---- package layout --------------------------------------------------------

begin "package() installs a self-locating tree"
make_sandbox
build=$SANDBOX/build/cachyos-agent
pkg=$SANDBOX/pkg
mkdir -p "$build"
tar -C "$REPO_ROOT" --exclude=./.git -cf - . | tar -C "$build" -xf -
if ! (cd "$SANDBOX/build" \
  && bash -c 'set -euo pipefail
              source cachyos-agent/PKGBUILD
              pkgdir=$1
              package' _ "$pkg" >/dev/null); then
  fail "package() failed to stage the layout"
else
  staged=$pkg/usr/share/cachyos-agent
  for name in cachyos-agent cachyos-agent-skills-provision; do
    if [[ ! -L $pkg/usr/bin/$name ]]; then
      fail "/usr/bin/$name is not a symlink"
    elif [[ $(readlink -f "$pkg/usr/bin/$name") != "$staged/bin/$name" ]]; then
      fail "/usr/bin/$name does not resolve to the real file under the data root"
    fi
  done
  [[ $(readlink -f "$pkg/usr/bin/cachyos-provision-agent-skills") == "$staged/bin/cachyos-agent-skills-provision" ]] \
    || fail "the old provisioner name is not a symlink to the new one"
  # Links made by cachyos-agent-system 0.1.x point into its data directory, which
  # pacman removes when this package replaces it.
  [[ -L $pkg/usr/share/cachyos-agent-system && $(readlink -f "$pkg/usr/share/cachyos-agent-system") == "$staged" ]] \
    || fail "the old data directory is not a symlink to the new one"
  [[ -f $pkg/usr/share/cachyos-agent-system/agents/skills/cachyos/SKILL.md ]] \
    || fail "an old skill link would not resolve through the compatibility path"
  [[ -f $staged/lib/common.sh ]] || fail "lib/common.sh is missing from the data root"
  [[ -f $staged/AGENTS.md ]] || fail "AGENTS.md is missing from the data root"
  [[ -f $staged/upstreams.tsv ]] || fail "upstreams.tsv is missing from the data root"
  [[ -f $staged/MAINTENANCE.md ]] || fail "MAINTENANCE.md is not resolvable beside AGENTS.md"
  [[ -f $pkg/usr/share/doc/cachyos-agent/THIRD_PARTY_NOTICES.md ]] \
    || fail "THIRD_PARTY_NOTICES.md is missing from package documentation"
  [[ -f $pkg/usr/share/licenses/cachyos-agent/LICENSE ]] || fail "LICENSE is missing"
  "$VALIDATE" "$staged" >/dev/null 2>&1 || fail "validator rejected the installed package layout"

  # Without PATH help, every lookup must start from the symlink's real path.
  if ! out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$pkg/usr/bin/cachyos-agent" commands --check 2>&1); then
    fail "staged /usr/bin/cachyos-agent could not check its commands: $out"
  fi
  [[ $(env -i HOME="$HOME" PATH=/usr/bin:/bin "$pkg/usr/bin/cachyos-agent" version) == "$(<"$REPO_ROOT/VERSION")" ]] \
    || fail "staged /usr/bin/cachyos-agent reports the wrong version"
  env -i HOME="$HOME" PATH=/usr/bin:/bin "$pkg/usr/bin/cachyos-provision-agent-skills" >/dev/null \
    || fail "the old provisioner name did not run"
  [[ $(readlink "$HOME/.claude/skills/cachyos") == "$staged/agents/skills/cachyos" ]] \
    || fail "the staged provisioner did not link the packaged skill"
fi
ok
cleanup_sandbox
