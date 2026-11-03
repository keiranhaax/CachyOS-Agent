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

# bad_tree: a copy of the repository in $SANDBOX (the validator also follows the links
# in AGENTS.md and the READMEs, so the files they name must be there), which a case
# then breaks in one place.
bad_tree() {
  tar -C "$REPO_ROOT" --exclude=.git --exclude=__pycache__ -cf - . | tar -C "$SANDBOX" -xf -
}

# rejected <what>: the validator must fail on $SANDBOX, and say <what> as one of its
# problems. Each case below breaks one thing, so a check that stops working cannot
# be hidden by another that still does.
rejected() {
  local status=0 out
  out=$("$VALIDATE" "$SANDBOX" 2>&1) || status=$?
  [[ $status -eq 1 ]] || fail "validator exited $status, not 1, for: $1"
  [[ $out == *"problem: "*"$1"* ]] || fail "validator did not report [$1]: $out"
  [[ $(grep -c '^problem: ' <<<"$out") == 1 ]] || fail "validator reported more than the one problem [$1]: $out"
}

begin "validate rejects a broken link"
make_sandbox
bad_tree
printf '[gone](missing-topic.md)\n' >>"$SANDBOX/agents/skills/cachyos/kernel.md"
rejected "kernel.md: broken link target: missing-topic.md"
ok
cleanup_sandbox

begin "validate rejects a frontmatter name that is not the directory's"
make_sandbox
bad_tree
sed -i 's/^name: cachyos$/name: wrong/' "$SANDBOX/agents/skills/cachyos/SKILL.md"
rejected "cachyos: frontmatter name does not match directory name"
ok
cleanup_sandbox

begin "validate rejects a topic file that AGENTS.md does not index"
make_sandbox
bad_tree
printf '# New topic\n' >"$SANDBOX/agents/skills/cachyos/newtopic.md"
printf '\n- [new](newtopic.md)\n' >>"$SANDBOX/agents/skills/cachyos/SKILL.md"
rejected "AGENTS.md: does not reference agents/skills/cachyos/newtopic.md"
ok
cleanup_sandbox

begin "validate rejects a topic file that SKILL.md does not list"
make_sandbox
bad_tree
printf '# New topic\n' >"$SANDBOX/agents/skills/cachyos/newtopic.md"
printf '\n- [new](agents/skills/cachyos/newtopic.md)\n' >>"$SANDBOX/AGENTS.md"
rejected "agents/skills/cachyos/SKILL.md: does not reference newtopic.md"
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

# ---- update and check-upstreams ----------------------------------------------

# Both run against local Git repositories, which `git ls-remote` and `git fetch` read
# by path, so nothing here needs a network. Without git there is nothing to run them
# against, and the cases below are the last in this file.
if ! command -v git >/dev/null; then
  printf 'UNVERIFIED update and check-upstreams: git is not installed\n'
  exit 0
fi

git_identity() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
  export GIT_CONFIG_NOSYSTEM=1
}

# update_fixture: $UP, a bare upstream, and $CK, a clone of it holding the smallest
# tree `skills update` accepts. Its provisioner and upstream checker are scripts
# of their own that only record that they ran in $SANDBOX/ran.
update_fixture() {
  git_identity
  UP=$SANDBOX/upstream.git
  CK=$SANDBOX/checkout
  git init -q --bare -b main "$UP"
  git clone -q "$UP" "$CK" 2>/dev/null
  mkdir -p "$CK/agents/skills/cachyos" "$CK/bin"
  printf -- '---\nname: cachyos\ndescription: t\n---\n# body\n' >"$CK/agents/skills/cachyos/SKILL.md"
  for tool in provision check-upstreams; do
    printf '#!/bin/bash\necho "%s $*" >>"%s/ran"\n' "$tool" "$SANDBOX" >"$CK/bin/cachyos-agent-skills-$tool"
    chmod +x "$CK/bin/cachyos-agent-skills-$tool"
  done
  git -C "$CK" add -A
  git -C "$CK" commit -qm first
  git -C "$CK" push -q -u origin main 2>/dev/null
}

# upstream_commit <message>: a commit on the upstream, made from a second clone.
upstream_commit() {
  rm -rf "$SANDBOX/other"
  git clone -q "$UP" "$SANDBOX/other" 2>/dev/null
  echo "$1" >"$SANDBOX/other/$1.txt"
  git -C "$SANDBOX/other" add -A
  git -C "$SANDBOX/other" commit -qm "$1"
  git -C "$SANDBOX/other" push -q origin main 2>/dev/null
}

# update <args...>: run `skills update`; $status and $out. The log of what ran stays in $SANDBOX/ran.
update() {
  status=0
  out=$("$AGENT" skills update "$@" 2>&1) || status=$?
}

begin "update refuses a checkout with local changes and runs nothing"
make_sandbox
update_fixture
upstream_commit ahead
before=$(git -C "$CK" rev-parse HEAD)
echo dirty >"$CK/untracked.txt"
update "$CK"
[[ $status -eq 1 && $out == *"refuse: checkout has local changes"* ]] || fail "a dirty checkout was not refused ($status): $out"
[[ $(git -C "$CK" rev-parse HEAD) == "$before" ]] || fail "the dirty checkout was moved"
[[ ! -e $SANDBOX/ran ]] || fail "the provisioner or the checker ran for a refused update: $(<"$SANDBOX/ran")"
ok
cleanup_sandbox

begin "update refuses a branch with no upstream"
make_sandbox
update_fixture
git -C "$CK" branch -q --unset-upstream
update "$CK"
[[ $status -eq 1 && $out == *"refuse: current branch has no configured upstream"* ]] || fail "a branch without an upstream was not refused ($status): $out"
[[ ! -e $SANDBOX/ran ]] || fail "something ran for a refused update"
ok
cleanup_sandbox

begin "update fast-forwards a checkout that is behind, then provisions and checks"
make_sandbox
update_fixture
upstream_commit ahead
update "$CK"
[[ $status -eq 0 ]] || fail "update exited $status: $out"
[[ $(git -C "$CK" rev-parse HEAD) == "$(git -C "$UP" rev-parse main)" ]] || fail "the checkout was not fast-forwarded"
[[ $(git -C "$CK" rev-list --merges --count HEAD) == 0 ]] || fail "update made a merge commit"
[[ $(<"$SANDBOX/ran") == "provision $CK/agents/skills"$'\n'"check-upstreams $CK" ]] || fail "the provisioner and the checker did not run, in that order: $(<"$SANDBOX/ran")"
ok
cleanup_sandbox

begin "update says a current checkout is current, and leaves one that is ahead alone"
make_sandbox
update_fixture
update "$CK"
[[ $status -eq 0 && $out == *"source checkout is current"* ]] || fail "a current checkout ($status): $out"
echo mine >"$CK/mine.txt"
git -C "$CK" add -A
git -C "$CK" commit -qm mine
mine=$(git -C "$CK" rev-parse HEAD)
update "$CK"
[[ $status -eq 0 && $out == *"local checkout is ahead of origin/main"* ]] || fail "an ahead checkout ($status): $out"
[[ $(git -C "$CK" rev-parse HEAD) == "$mine" ]] || fail "update moved a checkout that was ahead"
ok
cleanup_sandbox

begin "update refuses a diverged branch without merging"
make_sandbox
update_fixture
upstream_commit theirs
echo mine >"$CK/mine.txt"
git -C "$CK" add -A
git -C "$CK" commit -qm mine
mine=$(git -C "$CK" rev-parse HEAD)
update "$CK"
[[ $status -eq 1 && $out == *"have diverged"* ]] || fail "a diverged branch was not refused ($status): $out"
[[ $(git -C "$CK" rev-parse HEAD) == "$mine" && $(git -C "$CK" rev-list --merges --count HEAD) == 0 ]] || fail "update merged into a diverged branch"
[[ ! -e $SANDBOX/ran ]] || fail "something ran for a refused update"
ok
cleanup_sandbox

begin "update refuses a ROOT inside a larger checkout"
make_sandbox
update_fixture
mkdir -p "$CK/sub"
update "$CK/sub"
[[ $status -eq 1 && $out == *"refuse: ROOT is inside a larger Git checkout"* ]] || fail "a subdirectory of a checkout was accepted ($status): $out"
ok
cleanup_sandbox

# reviewed_fixture: $SRC, a repository with a reviewed commit and a later head that
# touches only other/, and $REVIEWED and $HEAD_COMMIT; and $ROOT holding a manifest.
reviewed_fixture() {
  git_identity
  SRC=$SANDBOX/source
  ROOT=$SANDBOX/root
  mkdir -p "$ROOT"
  git init -q -b main "$SRC"
  mkdir -p "$SRC/watched" "$SRC/other"
  echo 1 >"$SRC/watched/a"
  echo 1 >"$SRC/other/b"
  git -C "$SRC" add -A
  git -C "$SRC" commit -qm one
  REVIEWED=$(git -C "$SRC" rev-parse HEAD)
  echo 2 >"$SRC/other/b"
  git -C "$SRC" commit -qam two
  HEAD_COMMIT=$(git -C "$SRC" rev-parse HEAD)
}

# check <manifest rows...>: write ROOT/upstreams.tsv with those rows (tab-separated
# by the caller) and run `skills check-upstreams`; $status and $out.
check() {
  printf '%s\n' "$@" >"$ROOT/upstreams.tsv"
  status=0
  out=$("$AGENT" skills check-upstreams "$ROOT" 2>&1) || status=$?
}

begin "check-upstreams exits 0 for a current row and for a moved head with nothing in scope"
make_sandbox
reviewed_fixture
check "$(printf 'same\t%s\trefs/heads/main\t%s' "$SRC" "$HEAD_COMMIT")"
[[ $status -eq 0 && $out == *"current: same ${HEAD_COMMIT:0:12}"* && $out == *"all 1 reviewed upstream branch(es) are current"* ]] || fail "a current row ($status): $out"
check "$(printf 'scoped\t%s\trefs/heads/main\t%s\twatched' "$SRC" "$REVIEWED")"
[[ $status -eq 0 && $out == *"current in scope: scoped head moved ${REVIEWED:0:12} -> ${HEAD_COMMIT:0:12}; no changes under: watched"* ]] || fail "a moved head outside the scope ($status): $out"
ok
cleanup_sandbox

begin "check-upstreams exits 1 when a head moved and anything in scope changed"
make_sandbox
reviewed_fixture
check "$(printf 'plain\t%s\trefs/heads/main\t%s' "$SRC" "$REVIEWED")"
[[ $status -eq 1 && $out == *"review required: plain ${REVIEWED:0:12} -> ${HEAD_COMMIT:0:12}"* && $out == *"1 of 1 upstream branch(es) changed"* ]] || fail "a row without paths ($status): $out"
check "$(printf 'scoped\t%s\trefs/heads/main\t%s\tother' "$SRC" "$REVIEWED")"
[[ $status -eq 1 && $out == *"(1 in-scope commit(s) under: other)"* ]] || fail "a row with a change in scope ($status): $out"
check "$(printf 'same\t%s\trefs/heads/main\t%s' "$SRC" "$HEAD_COMMIT")" "$(printf 'plain\t%s\trefs/heads/main\t%s' "$SRC" "$REVIEWED")"
[[ $status -eq 1 && $out == *"current: same"* && $out == *"review required: plain"* && $out == *"1 of 2 upstream branch(es) changed"* ]] || fail "one row current, one not ($status): $out"
ok
cleanup_sandbox

begin "check-upstreams exits 2 when the check cannot be completed"
make_sandbox
reviewed_fixture
check "$(printf 'gone\t%s/nowhere\trefs/heads/main\t%s' "$SANDBOX" "$REVIEWED")"
[[ $status -eq 2 && $out == *"failed to query gone"* ]] || fail "an unreachable upstream ($status): $out"
check "$(printf 'bad\t%s\trefs/heads/main\tnot-a-commit' "$SRC")"
[[ $status -eq 2 && $out == *"invalid row"* ]] || fail "a row with no commit ($status): $out"
check "$(printf 'nobranch\t%s\trefs/heads/missing\t%s' "$SRC" "$REVIEWED")"
[[ $status -eq 2 && $out == *"no branch head returned for nobranch"* ]] || fail "a branch that is not there ($status): $out"
check "# only a comment"
[[ $status -eq 2 && $out == *"no upstream entries found"* ]] || fail "a manifest with no rows ($status): $out"
rm "$ROOT/upstreams.tsv"
status=0
out=$("$AGENT" skills check-upstreams "$ROOT" 2>&1) || status=$?
[[ $status -eq 2 && $out == *"cannot read upstream manifest"* ]] || fail "no manifest ($status): $out"
ok
cleanup_sandbox
