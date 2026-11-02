#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The cachyos-agent dispatcher (usage, version, commands, routing) and the
# functions in lib/common.sh.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
LIB=$REPO_ROOT/lib/common.sh
VERSION=$(<"$REPO_ROOT/VERSION")

# make_tree: $TREE, a private copy of the dispatcher with an empty bin/ to fill
# with fake commands, so tests control exactly which commands exist.
make_tree() {
  TREE=$SANDBOX/tree
  mkdir -p "$TREE/bin" "$TREE/lib"
  cp "$REPO_ROOT/bin/cachyos-agent" "$TREE/bin/"
  cp "$LIB" "$TREE/lib/"
  cp "$REPO_ROOT/VERSION" "$TREE/"
  TREE_AGENT=$TREE/bin/cachyos-agent
}

# add_command <name> [comment...]: an executable that prints "<name>:<its args>".
# Each comment goes into the header as written, e.g. cachyos-agent:summary=Hi.
add_command() {
  local name=$1 comment
  shift
  {
    printf '#!/bin/bash\n'
    for comment in "$@"; do printf '# %s\n' "$comment"; done
    printf 'echo "%s:$*"\n' "$name"
  } >"$TREE/bin/$name"
  chmod +x "$TREE/bin/$name"
}

# only_path <dir> <function> [args...]: run a function with PATH reduced to <dir>,
# so no real terminal or notify-send on this machine can answer a test.
only_path() {
  local dir=$1
  shift
  # shellcheck disable=SC2123 # narrowing PATH is the whole point
  (PATH=$dir; "$@")
}

# ---- usage, version -----------------------------------------------------------

begin "usage shows the version and the groups"
make_sandbox
out=$("$AGENT")
[[ $out == *"cachyos-agent $VERSION"* ]] || fail "usage does not show the version"
[[ $out == *Usage:* ]] || fail "usage has no Usage section"
for group in skills commands version; do
  [[ $out == *"  $group "* ]] || fail "usage does not list the $group group"
done
[[ $out == *"Provision, update, and validate the CachyOS skill"* ]] || fail "known group has no description"
[[ $("$AGENT" --help) == "$out" && $("$AGENT" -h) == "$out" ]] || fail "--help and -h differ from no arguments"
ok
cleanup_sandbox

begin "usage gives unknown groups a generic description"
make_sandbox
make_tree
add_command cachyos-agent-zebra "cachyos-agent:summary=Stripes"
[[ $("$TREE_AGENT") == *"zebra     zebra commands"* ]] || fail "unknown group is not listed with a generic description"
ok
cleanup_sandbox

begin "version prints VERSION"
make_sandbox
[[ $("$AGENT" version) == "$VERSION" ]] || fail "version output differs from VERSION"
ok
cleanup_sandbox

# ---- commands listing --------------------------------------------------------

begin "commands lists visible commands and --all adds hidden ones"
make_sandbox
make_tree
add_command cachyos-agent-foo "cachyos-agent:summary=The foo command"
add_command cachyos-agent-foo-bar "cachyos-agent:summary=Foo bar"
add_command cachyos-agent-quiet "cachyos-agent:summary=Not for the list" "cachyos-agent:hidden=true"
out=$("$TREE_AGENT" commands)
[[ $out == *"cachyos-agent foo "*"The foo command"* ]] || fail "foo is not listed with its summary"
[[ $out == *"cachyos-agent foo bar "*"Foo bar"* ]] || fail "foo bar is not listed"
[[ $out != *quiet* ]] || fail "a hidden command was listed"
[[ $("$TREE_AGENT" commands --all) == *"cachyos-agent quiet "*"Not for the list"* ]] \
  || fail "--all did not list the hidden command"
ok
cleanup_sandbox

begin "commands --json is valid JSON with every field"
make_sandbox
make_tree
add_command cachyos-agent-foo "cachyos-agent:summary=Say \"hi\" \\ there" "cachyos-agent:args=[--x] <thing>" \
  "cachyos-agent:examples=cachyos-agent foo a | cachyos-agent foo b"
add_command cachyos-agent-foo-bar "cachyos-agent:summary=Foo bar"
add_command cachyos-agent-quiet "cachyos-agent:hidden=true"
json=$("$TREE_AGENT" commands --json)
jq -e '.ok == true and (.commands | map(.binary) == ["cachyos-agent-foo", "cachyos-agent-foo-bar"])' <<<"$json" >/dev/null \
  || fail "unexpected command set: $json"
[[ $(jq -r '.commands[0].summary' <<<"$json") == 'Say "hi" \ there' ]] || fail "summary was not escaped faithfully"
jq -e '.commands[0] | .route == "cachyos-agent foo" and .group == "foo" and .name == "" and .args == "[--x] <thing>"
       and .examples == ["cachyos-agent foo a", "cachyos-agent foo b"] and .hidden == false' <<<"$json" >/dev/null \
  || fail "foo has the wrong fields: $(jq -c '.commands[0]' <<<"$json")"
jq -e '.commands[1] | .route == "cachyos-agent foo bar" and .group == "foo" and .name == "bar" and .examples == []' <<<"$json" >/dev/null \
  || fail "foo bar has the wrong fields"
jq -e '.commands | map(select(.hidden)) | map(.binary) == ["cachyos-agent-quiet"]' <<<"$("$TREE_AGENT" commands --json --all)" >/dev/null \
  || fail "--all --json did not mark the hidden command"
ok
cleanup_sandbox

begin "commands --json describes the real tree"
make_sandbox
jq -e '.ok and (.commands | map(.route) | contains(["cachyos-agent skills validate", "cachyos-agent skills provision"]))' \
  <<<"$("$AGENT" commands --json)" >/dev/null || fail "real commands are missing from --json"
ok
cleanup_sandbox

# ---- commands --check --------------------------------------------------------

begin "commands --check passes on the real tree"
make_sandbox
"$AGENT" commands --check >/dev/null || fail "the repository's own commands do not pass --check"
ok
cleanup_sandbox

begin "commands --check reports every kind of problem"
make_sandbox
make_tree
add_command cachyos-agent-fine "cachyos-agent:summary=Fine"
add_command cachyos-agent-secret "cachyos-agent:hidden=true"
add_command cachyos-agent-version "cachyos-agent:summary=Collides with the built-in version"
add_command cachyos-agent-nosummary
add_command cachyos-agent-broken "cachyos-agent:summary=Syntax error" && echo 'if then' >>"$TREE/bin/cachyos-agent-broken"
printf '#!/bin/bash\n# cachyos-agent:summary=No exec bit\n' >"$TREE/bin/cachyos-agent-plain"
printf '#!/usr/bin/env python3\n# cachyos-agent:summary=Bad python\ndef (\n' >"$TREE/bin/cachyos-agent-pybad"
chmod +x "$TREE/bin/cachyos-agent-pybad"
add_command cachyos-agent-usage "cachyos-agent:summary=Usage"
printf '#!/usr/bin/env python3\n# cachyos-agent:summary=Name the resolver cannot match\nprint("hi")\n' >"$TREE/bin/cachyos-agent-usage-collect.py"
chmod +x "$TREE/bin/cachyos-agent-usage-collect.py"
add_command "cachyos-agent-usage~" "cachyos-agent:summary=Editor backup"
if out=$("$TREE_AGENT" commands --check 2>&1); then
  fail "--check passed a tree with problems"
fi
[[ $out == *"duplicate route: cachyos-agent-version"* ]] || fail "duplicate route not reported: $out"
[[ $out == *"cachyos-agent-nosummary has no cachyos-agent:summary"* ]] || fail "missing summary not reported: $out"
[[ $out == *"cachyos-agent-plain is not executable"* ]] || fail "missing exec bit not reported: $out"
[[ $out == *"cachyos-agent-broken fails its syntax check"* ]] || fail "bash syntax error not reported: $out"
[[ $out == *"cachyos-agent-pybad fails its syntax check"* ]] || fail "python syntax error not reported: $out"
[[ $out == *"cachyos-agent-usage-collect.py is not reachable"* ]] || fail "a dotted name is not reported as unreachable: $out"
[[ $out == *"cachyos-agent-usage~ is not reachable"* ]] || fail "an editor backup is not reported as unreachable: $out"
[[ $out != *cachyos-agent-fine* && $out != *cachyos-agent-secret* && $out != *"cachyos-agent-usage is"* ]] \
  || fail "a valid or hidden command was reported: $out"
[[ -z $(find "$TREE" -name __pycache__) ]] || fail "py_compile left bytecode in the command directory"
ok
cleanup_sandbox

begin "commands --check accepts a valid Python command"
make_sandbox
make_tree
printf '#!/usr/bin/env python3\n# cachyos-agent:summary=Good python\nprint("hi")\n' >"$TREE/bin/cachyos-agent-py"
chmod +x "$TREE/bin/cachyos-agent-py"
"$TREE_AGENT" commands --check >/dev/null || fail "--check rejected valid Python"
ok
cleanup_sandbox

# ---- routing -----------------------------------------------------------------

begin "the longest matching command wins"
make_sandbox
make_tree
add_command cachyos-agent-foo "cachyos-agent:summary=Foo"
add_command cachyos-agent-foo-bar "cachyos-agent:summary=Foo bar"
add_command cachyos-agent-foo-bar-baz "cachyos-agent:summary=Foo bar baz"
[[ $("$TREE_AGENT" foo bar baz) == "cachyos-agent-foo-bar-baz:" ]] || fail "foo bar baz did not reach foo-bar-baz"
[[ $("$TREE_AGENT" foo bar qux) == "cachyos-agent-foo-bar:qux" ]] || fail "foo bar qux did not reach foo-bar with qux"
[[ $("$TREE_AGENT" foo qux) == "cachyos-agent-foo:qux" ]] || fail "foo qux did not reach foo with qux"
[[ $("$TREE_AGENT" foo) == "cachyos-agent-foo:" ]] || fail "bare foo did not reach foo"
[[ $("$TREE_AGENT" foo bar baz extra 'two words') == "cachyos-agent-foo-bar-baz:extra two words" ]] \
  || fail "arguments after the matched words were not passed through"
ok
cleanup_sandbox

begin "arguments never become part of a file name"
make_sandbox
make_tree
add_command cachyos-agent-foo "cachyos-agent:summary=Foo"
[[ $("$TREE_AGENT" foo ../x) == "cachyos-agent-foo:../x" ]] || fail "a path-like argument was not passed to foo"
[[ $("$TREE_AGENT" foo -- --bar) == "cachyos-agent-foo:-- --bar" ]] || fail "-- was not passed to foo"
if "$TREE_AGENT" '../foo' 2>/dev/null; then fail "a path-like command word was accepted"; fi
ok
cleanup_sandbox

begin "a hyphenated name matches the same command"
make_sandbox
make_tree
add_command cachyos-agent-skills-check-upstreams "cachyos-agent:summary=Check"
[[ $("$TREE_AGENT" skills check-upstreams) == "cachyos-agent-skills-check-upstreams:" ]] || fail "skills check-upstreams did not resolve"
[[ $("$TREE_AGENT" skills check upstreams x) == "cachyos-agent-skills-check-upstreams:x" ]] || fail "skills check upstreams did not resolve"
ok
cleanup_sandbox

begin "unknown commands exit 1 with a hint"
make_sandbox
make_tree
add_command cachyos-agent-foo "cachyos-agent:summary=Foo"
status=0
out=$("$TREE_AGENT" nonesuch a b 2>&1) || status=$?
[[ $status -eq 1 ]] || fail "unknown command exited $status, expected 1"
[[ $out == *"Unknown command: nonesuch a b"* ]] || fail "no Unknown command message: $out"
[[ $out == *"cachyos-agent commands"* ]] || fail "no hint to run cachyos-agent commands: $out"
ok
cleanup_sandbox

# ---- group help --------------------------------------------------------------

begin "group --help lists the group's commands with args and examples"
make_sandbox
out=$("$AGENT" skills --help)
[[ $out == *"cachyos-agent skills validate [ROOT]"* ]] || fail "validate and its args are missing: $out"
[[ $out == *"cachyos-agent skills provision [--force] [SKILLS_DIR]"* ]] || fail "provision and its args are missing"
[[ $out == *"e.g. cachyos-agent skills provision --force"* ]] || fail "examples are missing"
[[ $("$AGENT" skills -h) == "$out" ]] || fail "-h differs from --help"
ok
cleanup_sandbox

begin "a group answers --help itself, a lone command answers its own"
make_sandbox
make_tree
add_command cachyos-agent-multi "cachyos-agent:summary=Multi root" "cachyos-agent:args=<pid>"
add_command cachyos-agent-multi-mute "cachyos-agent:summary=Multi mute"
add_command cachyos-agent-lone "cachyos-agent:summary=Lone command"
out=$("$TREE_AGENT" multi --help)
[[ $out == *"cachyos-agent multi <pid>"* && $out == *"cachyos-agent multi mute"* ]] || fail "multi --help is not the group listing: $out"
[[ $out != *"cachyos-agent-multi:"* ]] || fail "multi --help ran the command"
[[ $("$TREE_AGENT" lone --help) == "cachyos-agent-lone:--help" ]] || fail "lone --help did not reach the command"
[[ $("$TREE_AGENT" multi mute --help) == "cachyos-agent-multi-mute:--help" ]] || fail "multi mute --help did not reach the command"
[[ $("$TREE_AGENT" multi) == "cachyos-agent-multi:" ]] || fail "bare multi did not run its own command"
ok
cleanup_sandbox

begin "a bare group without a command of its own shows group help"
make_sandbox
make_tree
add_command cachyos-agent-things-list "cachyos-agent:summary=List things"
out=$("$TREE_AGENT" things)
[[ $out == *"cachyos-agent things list"* ]] || fail "bare group did not list its commands: $out"
ok
cleanup_sandbox

# ---- through the real tree ---------------------------------------------------

begin "the real skills commands run through the dispatcher"
make_sandbox
"$AGENT" skills validate >/dev/null || fail "cachyos-agent skills validate failed"
ok
cleanup_sandbox

# ---- lib/common.sh -----------------------------------------------------------

make_sandbox
# shellcheck source=../../lib/common.sh
source "$LIB"

begin "the data root, config and state dirs follow the environment"
[[ $CACHYOS_AGENT_ROOT == "$REPO_ROOT" ]] || fail "root is $CACHYOS_AGENT_ROOT"
[[ $CACHYOS_AGENT_BIN == "$REPO_ROOT/bin" ]] || fail "bin dir is $CACHYOS_AGENT_BIN"
[[ $(bash -c 'echo "$CACHYOS_AGENT_BIN"') == "$REPO_ROOT/bin" ]] || fail "the bin dir is not exported"
[[ $CACHYOS_AGENT_CONFIG_DIR == "$HOME/.config/cachyos-agent" ]] || fail "config dir is $CACHYOS_AGENT_CONFIG_DIR"
[[ $CACHYOS_AGENT_STATE_DIR == "$HOME/.local/state/cachyos-agent" ]] || fail "state dir is $CACHYOS_AGENT_STATE_DIR"
[[ $(XDG_STATE_HOME=/elsewhere bash -c 'source "$1" && echo "$CACHYOS_AGENT_STATE_DIR"' _ "$LIB") == /elsewhere/cachyos-agent ]] \
  || fail "XDG_STATE_HOME is ignored"
ok

begin "ca_version and ca_cmd_present"
[[ $(ca_version) == "$VERSION" ]] || fail "ca_version differs from VERSION"
ca_cmd_present bash cat || fail "ca_cmd_present rejected real commands"
if ca_cmd_present bash no-such-command-xyz; then fail "ca_cmd_present accepted a missing command"; fi
# shellcheck disable=SC2329 # looked up by name, never called
shell_function() { :; }
if ca_cmd_present shell_function; then fail "ca_cmd_present accepted a shell function"; fi
ok

begin "ca_die prints to stderr and exits 1"
status=0
out=$( (ca_die "something broke") 2>&1 >/dev/null) || status=$?
[[ $status -eq 1 && $out == *"something broke"* ]] || fail "status $status, output: $out"
ok

begin "ca_flag switches flags on, off and toggles them"
ca_flag demo on
ca_flag_enabled demo || fail "demo is not enabled after on"
[[ -f $CACHYOS_AGENT_STATE_DIR/toggles/demo ]] || fail "flag file is not under the state dir"
ca_flag demo on
ca_flag demo off
if ca_flag_enabled demo; then fail "demo is still enabled after off"; fi
ca_flag demo off
ca_flag demo toggle
ca_flag_enabled demo || fail "toggle did not enable"
ca_flag demo toggle
if ca_flag_enabled demo; then fail "toggle did not disable"; fi
ca_flag crash-ignore/firefox on
ca_flag_enabled crash-ignore/firefox || fail "nested flag is not enabled"
[[ -f $CACHYOS_AGENT_STATE_DIR/toggles/crash-ignore/firefox ]] || fail "nested flag file is in the wrong place"
ca_flag_enabled crash-ignore/other && fail "an unrelated nested flag is enabled"
ok

begin "ca_flag rejects names that could leave the toggles directory"
for bad in ../escape a/../b a/b/c /abs . .. a/. a/.. '' 'x/'; do
  if (ca_flag "$bad" on) >/dev/null 2>&1; then fail "accepted flag name '$bad'"; fi
done
if (ca_flag demo sideways) >/dev/null 2>&1; then fail "accepted an unknown action"; fi
[[ ! -e $CACHYOS_AGENT_STATE_DIR/escape && ! -e $HOME/escape ]] || fail "a rejected name still wrote a file"
ok

begin "ca_flag takes any process name that fits in one path component"
for name in 'c++' '(sd-pam)' .kwin-wrapped 'foo@bar' 'chrome:cs0' 'two words' '-dash'; do
  ca_flag "crash-ignore/$name" on
  ca_flag_enabled "crash-ignore/$name" || fail "'crash-ignore/$name' is not enabled after on"
  [[ -f $CACHYOS_AGENT_STATE_DIR/toggles/crash-ignore/$name ]] || fail "'$name' is not stored under its own name"
  ca_flag "crash-ignore/$name" off
  if ca_flag_enabled "crash-ignore/$name"; then fail "'crash-ignore/$name' is still enabled after off"; fi
done
ca_flag .hidden on
ca_flag_enabled .hidden || fail "a leading dot is rejected"
ca_flag .hidden off
ok

begin "ca_flag_enabled answers false for a name it can never hold"
for name in crash-ignore/kworker/u16:2 crash-ignore/async-std/runti ../escape '' x/; do
  out=$( (ca_flag_enabled "$name" || echo "survived $?") 2>&1)
  [[ $out == "survived 1" ]] || fail "ca_flag_enabled '$name' printed: $out"
done
ok

begin "ca_atomic_write replaces the file and leaves no temp files"
target=$SANDBOX/out/deep/file.txt
printf 'one\n' | ca_atomic_write "$target"
[[ $(<"$target") == one ]] || fail "first write is wrong"
[[ $(stat -c %a "$target") == 600 ]] || fail "mode is $(stat -c %a "$target"), not 0600"
printf 'two\n' | ca_atomic_write "$target"
[[ $(<"$target") == two ]] || fail "rewrite is wrong"
[[ $(stat -c %a "$target") == 600 ]] || fail "rewritten mode is $(stat -c %a "$target"), not 0600"
[[ $(ls -A "$SANDBOX/out/deep") == file.txt ]] || fail "temp files were left behind: $(ls -A "$SANDBOX/out/deep")"
ok

begin "ca_atomic_write keeps the last good file when its producer wrote nothing"
target=$SANDBOX/out/usage.json
printf '{"good":1}\n' | ca_atomic_write "$target"
status=0
(set -o pipefail; false | ca_atomic_write "$target") 2>/dev/null || status=$?
[[ $status -ne 0 ]] || fail "empty input was accepted"
[[ $(<"$target") == '{"good":1}' ]] || fail "the last good file was replaced: $(<"$target")"
[[ -z $(find "$SANDBOX/out" -name 'usage.json.*') ]] || fail "temp file left behind: $(find "$SANDBOX/out" -name 'usage.json.*')"
rm "$target"
if ca_atomic_write "$target" </dev/null 2>/dev/null; then fail "empty input was accepted for a new file"; fi
[[ ! -e $target ]] || fail "an empty file was created"
ok

begin "ca_atomic_write writes through a symlink and keeps the link"
mkdir -p "$SANDBOX/dotfiles"
printf 'old\n' >"$SANDBOX/dotfiles/real.json"
ln -s "$SANDBOX/dotfiles/real.json" "$SANDBOX/out/link.json"
printf 'new\n' | ca_atomic_write "$SANDBOX/out/link.json"
[[ -L $SANDBOX/out/link.json ]] || fail "the symlink was replaced by a regular file"
[[ $(<"$SANDBOX/dotfiles/real.json") == new ]] || fail "the link target was not updated"
ln -s "$SANDBOX/dotfiles/later/dangling.json" "$SANDBOX/out/dangling.json"
printf 'made\n' | ca_atomic_write "$SANDBOX/out/dangling.json"
[[ $(<"$SANDBOX/dotfiles/later/dangling.json") == made ]] || fail "a dangling link was not written through"
[[ -z $(find "$SANDBOX/dotfiles" -name '*.??????' -type f) ]] || fail "temp files were left behind"
ok

begin "ca_atomic_write leaves no temp file when the move fails"
target=$SANDBOX/out/moved.txt
printf 'keep\n' >"$target"
stub mv 'exit 1'
status=0
printf 'lost\n' | ca_atomic_write "$target" 2>/dev/null || status=$?
rm "$SANDBOX/stubs/mv"
[[ $status -ne 0 ]] || fail "a failed mv was reported as success"
[[ $(<"$target") == keep ]] || fail "the file changed although mv failed"
[[ -z $(find "$SANDBOX/out" -name 'moved.txt.*') ]] || fail "temp file left behind: $(find "$SANDBOX/out" -name 'moved.txt.*')"
ok

begin "ca_atomic_write removes its temp file when the process is terminated"
target=$SANDBOX/out/killed.txt
mkfifo "$SANDBOX/in"
# setsid gives the writer its own process group, so one signal reaches it and
# its subshell the way systemd or a terminal would.
# shellcheck disable=SC2016 # the snippet is meant to expand in the child shell
setsid bash -c 'source "$1"; ca_atomic_write "$2" <"$3"' _ "$LIB" "$target" "$SANDBOX/in" 2>/dev/null &
writer=$!
exec 3>"$SANDBOX/in"
for _ in {1..100}; do
  [[ -n $(find "$SANDBOX/out" -name 'killed.txt.*') ]] && break
  sleep 0.05
done
[[ -n $(find "$SANDBOX/out" -name 'killed.txt.*') ]] || fail "the writer never created its temp file"
kill -TERM -- "-$writer"
wait "$writer" 2>/dev/null || true
exec 3>&-
[[ -z $(find "$SANDBOX/out" -name 'killed.txt.*') ]] || fail "temp file survived SIGTERM: $(find "$SANDBOX/out" -name 'killed.txt.*')"
[[ ! -e $target ]] || fail "a terminated write still produced the file"
ok

begin "ca_notify falls back to stderr without notify-send or a bus"
out=$(only_path "$SANDBOX/empty" ca_notify -u critical -- '--hint=x' 'the body' 2>&1)
[[ $out == "--hint=x: the body" ]] || fail "without notify-send: $out"
stub notify-send
out=$(ca_notify 'Only summary' 2>&1)
[[ $out == "Only summary" ]] || fail "without a session bus: $out"
[[ ! -e $SANDBOX/calls/notify-send ]] || fail "notify-send ran without a session bus"
ok

begin "ca_notify passes user text after -- so it can never be an option"
export DBUS_SESSION_BUS_ADDRESS=unix:path=$SANDBOX/bus
ca_notify -u low -i dialog-warning -- '--hint=int:x:1' '-rf'
expected=$(printf '%s\n' --app-name=cachyos-agent -u low -i dialog-warning -- '--hint=int:x:1' -rf '')
[[ $(<"$SANDBOX/calls/notify-send") == "$expected" ]] || fail "unexpected notify-send argv: $(<"$SANDBOX/calls/notify-send")"
rm "$SANDBOX/calls/notify-send"
ca_notify '--looks-like-an-option'
expected=$(printf '%s\n' --app-name=cachyos-agent -- --looks-like-an-option '')
[[ $(<"$SANDBOX/calls/notify-send") == "$expected" ]] || fail "a leading-dash summary was not kept positional"
stub notify-send 'exit 1'
out=$(ca_notify 'Daemon down' 'try later' 2>&1)
[[ $out == "Daemon down: try later" ]] || fail "a failing notify-send did not fall back to stderr: $out"
unset DBUS_SESSION_BUS_ADDRESS
ok

# check_terminal <terminal> <words expected before the command>: with only that
# terminal installed, the command must arrive as separate argv words.
check_terminal() {
  local term=$1 expected
  shift
  rm -f "$SANDBOX"/stubs/* "$SANDBOX"/calls/*
  stub "$term"
  only_path "$SANDBOX/stubs" ca_terminal_exec --title 'My Title' agent 'two words' --flag
  expected=$(printf '%s\n' "$@" agent 'two words' --flag '')
  [[ $(<"$SANDBOX/calls/$term") == "$expected" ]] || fail "$term got: $(<"$SANDBOX/calls/$term")"
}

begin "ca_terminal_exec uses each terminal's own way to run a command"
check_terminal konsole -p 'tabtitle=My Title' -e
check_terminal alacritty -T 'My Title' -e
check_terminal kitty --title 'My Title'
check_terminal foot --title 'My Title'
check_terminal ghostty '--title=My Title' -e
check_terminal xterm -T 'My Title' -e
ok

# Konsole reads -p values as key=value;key=value and expands % codes in titles.
begin "ca_terminal_exec keeps a konsole title from being read as profile syntax"
rm -f "$SANDBOX"/stubs/* "$SANDBOX"/calls/*
stub konsole
only_path "$SANDBOX/stubs" ca_terminal_exec --title 'Crash: a;b;Environment=FOO=1 100%n' agent
expected=$(printf '%s\n' -p 'tabtitle=Crash: a b Environment=FOO=1 100 n' -e agent '')
[[ $(<"$SANDBOX/calls/konsole") == "$expected" ]] || fail "konsole got: $(<"$SANDBOX/calls/konsole")"
ok

begin "ca_terminal_exec prefers TERMINAL, then konsole, then alacritty"
rm -f "$SANDBOX"/stubs/* "$SANDBOX"/calls/*
stub myterm
stub konsole
stub alacritty
TERMINAL=myterm only_path "$SANDBOX/stubs" ca_terminal_exec agent 'two words'
[[ $(<"$SANDBOX/calls/myterm") == "$(printf '%s\n' -e agent 'two words' '')" ]] || fail "TERMINAL was not used with -e"
[[ ! -e $SANDBOX/calls/konsole ]] || fail "konsole ran although TERMINAL was set"
TERMINAL=missing-terminal only_path "$SANDBOX/stubs" ca_terminal_exec agent
[[ -e $SANDBOX/calls/konsole && ! -e $SANDBOX/calls/alacritty ]] || fail "an unusable TERMINAL did not fall back to konsole"
rm "$SANDBOX/stubs/konsole" "$SANDBOX/calls/konsole"
only_path "$SANDBOX/stubs" ca_terminal_exec agent
[[ -e $SANDBOX/calls/alacritty ]] || fail "alacritty was not the fallback after konsole"
ok

begin "ca_terminal_exec fails clearly without a terminal or a command"
status=0
out=$(only_path "$SANDBOX/empty" ca_terminal_exec agent 2>&1) || status=$?
[[ $status -eq 1 && $out == *"no terminal found"* ]] || fail "no terminal: status $status, output: $out"
if (ca_terminal_exec --title only) >/dev/null 2>&1; then fail "accepted a missing command"; fi
ok

begin "ca_syntax_ok checks bash and Python without leaving bytecode"
mkdir -p "$SANDBOX/syntax"
printf '#!/bin/bash\necho fine\n' >"$SANDBOX/syntax/good.sh"
printf '#!/bin/bash\nif then\n' >"$SANDBOX/syntax/bad.sh"
printf '#!/usr/bin/env python3\nprint(1)\n' >"$SANDBOX/syntax/good.py"
printf '#!/usr/bin/env python3\ndef (\n' >"$SANDBOX/syntax/bad.py"
ca_syntax_ok "$SANDBOX/syntax/good.sh" || fail "rejected valid bash"
ca_syntax_ok "$SANDBOX/syntax/good.py" || fail "rejected valid Python"
if ca_syntax_ok "$SANDBOX/syntax/bad.sh"; then fail "accepted broken bash"; fi
if ca_syntax_ok "$SANDBOX/syntax/bad.py"; then fail "accepted broken Python"; fi
[[ -z $(find "$SANDBOX/syntax" -name __pycache__) ]] || fail "bytecode was written next to the script"
ok

begin "ca_syntax_ok treats a .py file as Python even without a shebang"
printf 'print(1)\n' >"$SANDBOX/syntax/lib_good.py"
printf 'def (\n' >"$SANDBOX/syntax/lib_bad.py"
ca_syntax_ok "$SANDBOX/syntax/lib_good.py" || fail "rejected valid Python"
if ca_syntax_ok "$SANDBOX/syntax/lib_bad.py"; then fail "accepted broken Python"; fi
ok

cleanup_sandbox
