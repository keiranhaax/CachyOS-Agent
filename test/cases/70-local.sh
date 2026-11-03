#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# cachyos-agent local: recipe parsing, what fits a machine, use, start, stop,
# status and remove, with ollama, nvidia-smi, sudo, systemctl and pacman stubbed.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

AGENT=$REPO_ROOT/bin/cachyos-agent
OUT='' RC=0

# make_tree: $TREE_AGENT, a private copy of the dispatcher and the command whose
# recipes are three fixture rows, strongest first, so fit decisions do not move
# when data/local-models.tsv does.
make_tree() {
  local tree=$SANDBOX/tree
  mkdir -p "$tree/bin" "$tree/lib" "$tree/data"
  cp "$REPO_ROOT/bin/cachyos-agent" "$REPO_ROOT/bin/cachyos-agent-local" "$tree/bin/"
  cp "$REPO_ROOT/lib/common.sh" "$tree/lib/"
  cp "$REPO_ROOT/VERSION" "$tree/"
  {
    printf '# fixture recipes\n\n'
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      huge huge:120b 80 96 65536 66 'the large one' \
      mid mid:30b 24 32 32768 19 'the middle one' \
      tiny tiny:1b 8 16 32768 1 'the small one'
  } >"$tree/data/local-models.tsv"
  TREE=$tree
  TREE_AGENT=$tree/bin/cachyos-agent
}

# set_machine <cards> <ram_gib>: what the command will see. <cards> is a list of
# NVIDIA cards, or "none" for an nvidia-smi that fails the way it does without a
# driver. A card is the MiB nvidia-smi prints for it, optionally followed by
# @<compute capability> (8.9 when left out): "8188" or "16384@6.1".
set_machine() {
  local card cc lines=''
  printf 'MemTotal:       %d kB\nMemFree:           1024 kB\n' $(($2 * 1048576)) >"$SANDBOX/meminfo"
  export CACHYOS_AGENT_MEMINFO=$SANDBOX/meminfo CACHYOS_AGENT_DRM_DIR=$SANDBOX/drm
  if [[ $1 == none ]]; then
    stub nvidia-smi 'exit 9'
    return 0
  fi
  for card in $1; do
    cc=8.9
    if [[ $card == *@* ]]; then cc=${card#*@}; fi
    lines+=" '${card%@*}, $cc'"
  done
  stub nvidia-smi "printf '%s\\n'$lines"
}

# set_free <bytes>: what the stubbed df reports as available.
set_free() {
  stub df "printf '%s\\n' Avail $1"
}

# add_amd_card <n> <bytes>: a card directory as amdgpu exposes it.
add_amd_card() {
  mkdir -p "$SANDBOX/drm/card$1/device"
  printf '%s\n' "$2" >"$SANDBOX/drm/card$1/device/mem_info_vram_total"
}

# fake_service: stubs for ollama, systemctl, sudo and pacman that share one
# state: $SANDBOX/running exists while the service runs, installed holds what
# `ollama list` prints, ps what `ollama ps` prints, pull-fails makes a pull
# fail, create-fails makes a create fail, and create-hangs makes a create record
# create-started and wait on the hang fifo for a signal. `systemctl enable|start`
# begins the service, stop ends it, by-hand makes the server answer without the unit
# being active, and the stubbed pacman makes an ollama
# appear, as installing the package would. `pacman -Q <pkg>` succeeds unless
# not-installed-<pkg> exists, and installing <pkg> removes that file. df reports
# 10 TB free on the models directory, a directory in the sandbox, unless a test
# stubs it again.
# Without install_ollama the stubbed ollama is present from the start.
# shellcheck disable=SC2016 # the stub bodies are scripts, not strings to expand here
fake_service() {
  mkdir -p "$SANDBOX/pkg"
  stub ollama '
state=${self%/stubs/*}
case $1 in
  list) [[ -e $state/running ]] || exit 1; if [[ -f $state/installed ]]; then cat "$state/installed"; fi ;;
  ps) if [[ -f $state/ps ]]; then cat "$state/ps"; fi ;;
  pull) if [[ -e $state/pull-fails ]]; then echo "pull failed" >&2; exit 1; fi ;;
  create)
    if [[ -e $state/create-fails ]]; then echo "create failed" >&2; exit 1; fi
    if [[ -e $state/create-hangs ]]; then : >"$state/create-started"; exec 3<>"$state/hang"; read -r -t 30 -u 3 _ || true; fi
    cp "$4" "$state/modelfile"; echo "$OLLAMA_HOST" >"$state/host" ;;
esac
exit 0'
  stub systemctl '
state=${self%/stubs/*}
case $1 in
  is-active)
    if [[ -e $state/running && ! -e $state/by-hand ]]; then [[ ${2-} == --quiet ]] || echo active; exit 0; fi
    [[ ${2-} == --quiet ]] || echo inactive
    exit 3 ;;
  start | enable) : >"$state/running" ;;
  stop) rm -f "$state/running" ;;
esac
exit 0'
  stub sudo 'exec "$@"'
  stub pacman '
state=${self%/stubs/*}
if [[ $1 == -Q ]]; then [[ ! -e $state/not-installed-$2 ]]; exit; fi
rm -f "$state/not-installed-${!#}"
if [[ -x $state/pkg/ollama ]]; then cp "$state/pkg/ollama" "$state/stubs/ollama"; fi'
  stub sleep
  stub df 'printf "%s\n" Avail 9999999999999'
  mkdir -p "$SANDBOX/models"
  export CACHYOS_AGENT_MODELS_DIR=$SANDBOX/models
}

# narrow_path: narrow PATH to what the command really needs plus the stubs, so
# a tool on the machine running the tests (an ollama, a sudo, a pacman) cannot
# answer. Sets NARROW for use as PATH=$NARROW run ...
narrow_path() {
  local tool
  mkdir -p "$SANDBOX/real"
  for tool in dirname readlink mkdir mktemp mv cat rm cp; do
    ln -sf "$(type -P "$tool")" "$SANDBOX/real/$tool"
  done
  NARROW=$SANDBOX/stubs:$SANDBOX/real
}

# install_ollama: take the stubbed ollama off PATH until the stubbed pacman
# installs it, and narrow PATH as narrow_path does.
install_ollama() {
  mv "$SANDBOX/stubs/ollama" "$SANDBOX/pkg/ollama"
  narrow_path
}

# run <args...>: the dispatcher of the private tree with stdin closed. Never
# aborts the case; the output (both streams) lands in OUT and the status in RC.
run() {
  OUT=$("$TREE_AGENT" "$@" 2>&1 </dev/null) && RC=0 || RC=$?
}

# answer <text> <args...>: the same with <text> typed on stdin.
answer() {
  local text=$1
  shift
  OUT=$("$TREE_AGENT" "$@" 2>&1 <<<"$text") && RC=0 || RC=$?
}

# calls <cmd>: one line per recorded call of a stub, arguments joined by spaces.
calls() {
  local file=$SANDBOX/calls/$1 line args=''
  [[ -f $file ]] || return 0
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      args+=${args:+ }$line
    else
      printf '%s\n' "$args"
      args=''
    fi
  done <"$file"
}

# expect_calls <cmd> <line>...: the stub was called exactly like this, in order.
expect_calls() {
  local cmd=$1 want got
  shift
  want=$(printf '%s\n' "$@")
  got=$(calls "$cmd")
  [[ $got == "$want" ]] || fail "$cmd calls differ. wanted: ${want//$'\n'/ ; } got: ${got//$'\n'/ ; }"
}

expect_no_calls() {
  [[ ! -s $SANDBOX/calls/$1 ]] || fail "$1 was called: $(calls "$1")"
}

expect_in() {
  [[ $OUT == *"$1"* ]] || fail "output lacks: $1 (output: $OUT)"
}

# expect_row <id> <fit>: list shows a row of that id with that fit.
expect_row() {
  grep -Eq "^[ *] $1 +[^ ]+ +[0-9]+K +[0-9]+ GB +$2 " <<<"$OUT" || fail "$1 is not listed as $2 (output: $OUT)"
}

state_dir() {
  printf '%s\n' "$XDG_STATE_HOME/cachyos-agent/local"
}

# ---- the shipped recipes --------------------------------------------------------

begin "data/local-models.tsv: unique ids, numeric limits, an Ollama tag, a context an agent can use, a download size"
make_sandbox
set_machine 8188 64
declare -A seen=()
rows=0
while IFS=$'\t' read -r id model vram ram ctx download note; do
  [[ -n $id && $id != '#'* ]] || continue
  rows=$((rows + 1))
  [[ -z ${seen[$id]+x} ]] || fail "duplicate id $id"
  seen[$id]=1
  [[ $id =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "bad id $id"
  [[ $model =~ ^[a-z0-9._/-]+:[A-Za-z0-9._-]+$ ]] || fail "$id: $model is not name:tag"
  [[ $vram =~ ^[1-9][0-9]*$ && $ram =~ ^[1-9][0-9]*$ ]] || fail "$id: limits are not positive numbers without a leading zero"
  if ! [[ $ctx =~ ^[1-9][0-9]*$ ]] || ((ctx < 32768)); then fail "$id: context $ctx is not a number an agent can use"; fi
  if ! [[ $download =~ ^[1-9][0-9]*$ ]] || ((download >= ram)); then fail "$id: download_gb $download is not a size smaller than min_ram_gib $ram"; fi
  [[ -n $note ]] || fail "$id: no note"
done <"$REPO_ROOT/data/local-models.tsv"
((rows >= 5)) || fail "only $rows recipes"
run_real=$("$AGENT" local list 2>&1 </dev/null)
for id in "${!seen[@]}"; do
  [[ $run_real == *" $id "* ]] || fail "list through the real dispatcher does not show $id"
done
grep -Eq '^#.*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$REPO_ROOT/data/local-models.tsv" || fail "the header does not record the date the tags were checked"
ok
cleanup_sandbox

# ---- list: what fits ------------------------------------------------------------

begin "list on a small machine says what fits and why the rest does not"
make_sandbox
make_tree
set_machine 8188 32
run local list
((RC == 0)) || fail "list exited $RC: $OUT"
expect_in "This machine: NVIDIA GPU with 8 GiB VRAM, 32 GiB RAM"
expect_row tiny gpu
expect_row mid cpu
expect_row huge no
expect_in "needs 24 GiB VRAM to stay on the GPU; this GPU has 8 GiB, so the rest runs from RAM, slower"
expect_in "needs 96 GiB RAM or 80 GiB VRAM; this machine has 32 GiB RAM and 8 GiB VRAM"
expect_in "cachyos-agent local use best picks tiny."
expect_calls nvidia-smi "--query-gpu=memory.total,compute_cap --format=csv,noheader,nounits"
ok
cleanup_sandbox

begin "list on a large machine fits everything and picks the strongest model"
make_sandbox
make_tree
set_machine "49152 49152" 128
run local list
expect_in "NVIDIA GPU with 96 GiB VRAM, 128 GiB RAM"
expect_row huge gpu
expect_row mid gpu
expect_row tiny gpu
expect_in "cachyos-agent local use best picks huge."
ok
cleanup_sandbox

begin "list without a GPU runs models from RAM and says so"
make_sandbox
make_tree
set_machine none 20
run local list
expect_in "This machine: no supported GPU, 20 GiB RAM"
expect_row tiny cpu
expect_row mid no
expect_in "no supported GPU, so it runs from the 20 GiB of RAM, slowly"
expect_in "picks tiny."
ok
cleanup_sandbox

begin "list reads AMD VRAM from sysfs and adds the cards together"
make_sandbox
make_tree
set_machine none 16
add_amd_card 0 17179869184
add_amd_card 1 8589934592
mkdir -p "$SANDBOX/drm/card2/device" # an Intel card has no mem_info_vram_total
run local list
expect_in "This machine: AMD GPU with 24 GiB VRAM, 16 GiB RAM"
expect_row mid gpu
expect_row tiny gpu
expect_in "picks mid."
ok
cleanup_sandbox

begin "list counts only NVIDIA cards with compute capability 7.5 or newer, the floor of the CUDA build"
make_sandbox
make_tree
set_machine "8188@6.1" 32
run local list
expect_in "This machine: no supported GPU, 32 GiB RAM"
expect_row tiny cpu
# 16384@6.1 and 8188@7.4 are too old; 24576@7.5, 8188@10.0 and 8188@12.0 are
# not, so the sum is 8188 + 24576 + 8188 + 8188 MiB, 48 GiB.
set_machine "16384@6.1 8188 24576@7.5 8188@7.4 8188@10.0 8188@12.0" 32
run local list
expect_in "This machine: NVIDIA GPU with 48 GiB VRAM, 32 GiB RAM"
ok
cleanup_sandbox

begin "list reads only well-formed nvidia-smi lines"
make_sandbox
make_tree
set_machine none 32
stub nvidia-smi "printf '%s\\n' 'NVIDIA-SMI has failed 99999, 8.9' '99999 MiB, 8.9' '99999, 8.9 extra' 'x99999, 8.9' '99999, 8.9x' '99999, [N/A]' '[N/A], 8.9' '99999' '' ' 8188 , 8.9 ' '4096,8.9'"
run local list
expect_in "This machine: NVIDIA GPU with 12 GiB VRAM, 32 GiB RAM"
ok
cleanup_sandbox

begin "list does not take an AMD integrated GPU's carve-out for a GPU, but counts a card of 4 GiB or more"
make_sandbox
make_tree
set_machine none 32
add_amd_card 0 536870912
run local list
expect_in "This machine: no supported GPU, 32 GiB RAM"
add_amd_card 0 4294967295
run local list
expect_in "This machine: no supported GPU, 32 GiB RAM"
add_amd_card 0 4294967296
run local list
expect_in "This machine: AMD GPU with 4 GiB VRAM, 32 GiB RAM"
add_amd_card 0 17179869184
add_amd_card 1 536870912
run local list
expect_in "This machine: AMD GPU with 16 GiB VRAM, 32 GiB RAM"
ok
cleanup_sandbox

begin "list when nothing fits says so, and use best refuses"
make_sandbox
make_tree
set_machine none 4
run local list
expect_row tiny no
expect_row huge no
expect_in "No recipe fits this machine."
run local use best
((RC == 1)) || fail "use best exited $RC on a machine nothing fits"
expect_in "no recipe fits this machine"
expect_no_calls ollama
ok
cleanup_sandbox

begin "list marks the active model"
make_sandbox
make_tree
set_machine 8188 32
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
run local list
grep -Eq '^\* mid ' <<<"$OUT" || fail "mid is not marked active: $OUT"
grep -Eq '^  tiny ' <<<"$OUT" || fail "tiny is marked active: $OUT"
expect_in "* marks the model cachyos-agent launch --local opens an agent on."
ok
cleanup_sandbox

begin "a malformed or duplicate recipe row stops with its line number"
make_sandbox
set_machine 8188 32
rows=(
  $'broken\tbroken:1b\tmany\t16\t32768\t2\tvram is not a number'
  $'broken\tbroken:1b\t8\tmany\t32768\t2\tram is not a number'
  $'broken\tbroken:1b\t8\t16\tbig\t2\tcontext is not a number'
  $'broken\tbroken:1b\t8\t16\t32768\tbig\tdownload is not a number'
  $'broken\tbroken:1b\t08\t16\t32768\t2\tvram has a leading zero, which bash reads as octal'
  $'broken\tbroken:1b\t8\t010\t32768\t2\tram has a leading zero'
  $'broken\tbroken:1b\t8\t16\t032768\t2\tcontext has a leading zero'
  $'broken\tbroken:1b\t8\t16\t32768\t02\tdownload has a leading zero'
  $'broken\tbroken:1b\t0\t16\t32768\t2\tvram is zero'
  $'broken\tbroken:1b\t8\t0\t32768\t2\tram is zero'
  $'broken\tbroken:1b\t8\t16\t0\t2\tcontext is zero'
  $'broken\tbroken:1b\t8\t16\t32768\t0\tdownload is zero'
  $'broken\tbroken:1b\t8\t16\t32768\tthe download column is missing'
  $'broken\tbroken:1b\t8\t16\t32768\t2'
  $'broken\tbroken:1b\t8\t16\t32768\t2\t'
  $'Broken\tbroken:1b\t8\t16\t32768\t2\tid has a capital'
  $'broken\ttwo words\t8\t16\t32768\t2\tmodel has a space'
  'broken broken:1b 8 16 32768 2 spaces instead of tabs'
)
for row in "${rows[@]}"; do
  make_tree
  printf '%s\n' "$row" >>"$TREE/data/local-models.tsv"
  run local list
  ((RC == 1)) || fail "row '$row' exited $RC"
  expect_in "local-models.tsv:6: malformed recipe row"
done
make_tree
printf 'tiny\tother:2b\t8\t16\t32768\t2\tsame id again\n' >>"$TREE/data/local-models.tsv"
run local list
((RC == 1)) || fail "duplicate id exited $RC"
expect_in "local-models.tsv:6: duplicate recipe id tiny"
make_tree
printf '# only a comment\n\n' >"$TREE/data/local-models.tsv"
run local list
((RC == 1)) || fail "an empty recipe file exited $RC"
expect_in "has no recipes"
ok
cleanup_sandbox

begin "RAM is MemTotal rounded to the nearest GiB, as a 64 GiB machine reports 63"
make_sandbox
make_tree
set_machine none 1
printf 'MemTotal:       65665276 kB\nMemFree:           1024 kB\n' >"$SANDBOX/meminfo"
run local list
expect_in "no supported GPU, 63 GiB RAM"
printf 'MemTotal:       33134387 kB\n' >"$SANDBOX/meminfo"
run local list
expect_in "32 GiB RAM"
expect_row mid cpu
ok
cleanup_sandbox

# ---- use ------------------------------------------------------------------------

begin "use best downloads the model, builds it with the recipe's context and records it as active"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
export OLLAMA_HOST=elsewhere:9
run local use best
((RC == 0)) || fail "use best exited $RC: $OUT"
expect_in "Best fit for this machine: tiny"
expect_in "cachyos-agent launch --local"
expect_in "http://127.0.0.1:11434/v1"
[[ $(calls ollama) == "list"$'\n'"list"$'\n'"pull tiny:1b"$'\n'"create tiny -f "* ]] \
  || fail "ollama calls were: $(calls ollama)"
[[ $(<"$SANDBOX/modelfile") == $'FROM tiny:1b\nPARAMETER num_ctx 32768' ]] || fail "Modelfile was: $(<"$SANDBOX/modelfile")"
[[ $(<"$SANDBOX/host") == 127.0.0.1:11434 ]] || fail "ollama talked to $(<"$SANDBOX/host") instead of the endpoint it prints"
[[ $(<"$(state_dir)/active") == tiny ]] || fail "active is not tiny"
expect_no_calls sudo
compgen -G "$(state_dir)/Modelfile.*" >/dev/null && fail "a temporary Modelfile was left behind"
unset OLLAMA_HOST
run local use best
((RC == 0)) || fail "running use a second time exited $RC"
[[ $(<"$(state_dir)/active") == tiny ]] || fail "active changed on the second run"
ok
cleanup_sandbox

begin "use <id> on a model that only fits with help from RAM warns and goes ahead"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
run local use mid
((RC == 0)) || fail "use mid exited $RC: $OUT"
expect_in "Note: needs 24 GiB VRAM to stay on the GPU; this GPU has 8 GiB"
expect_in "mid: the middle one"
[[ $(<"$(state_dir)/active") == mid ]] || fail "active is not mid"
[[ $(<"$SANDBOX/modelfile") == $'FROM mid:30b\nPARAMETER num_ctx 32768' ]] || fail "Modelfile was: $(<"$SANDBOX/modelfile")"
ok
cleanup_sandbox

begin "use refuses a model that does not fit before touching anything"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
mkdir -p "$(state_dir)"
printf 'tiny\n' >"$(state_dir)/active"
run local use huge
((RC == 1)) || fail "use huge exited $RC"
expect_in "huge does not fit this machine: needs 96 GiB RAM or 80 GiB VRAM"
expect_no_calls ollama
expect_no_calls sudo
[[ $(<"$(state_dir)/active") == tiny ]] || fail "active changed"
ok
cleanup_sandbox

begin "use rejects unknown recipes, text that is not an id, and a wrong argument count"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
for bad in nope ../x '@' '*' 'a b' ''; do
  run local use "$bad"
  ((RC == 1)) || fail "use '$bad' exited $RC"
  expect_in "unknown recipe"
done
run local use
((RC == 2)) || fail "use with no argument exited $RC"
expect_in "use needs best or a recipe id"
run local use tiny mid
((RC == 2)) || fail "use with two arguments exited $RC"
expect_no_calls ollama
expect_no_calls sudo
ok
cleanup_sandbox

begin "use keeps the previous active model when the download or the model build fails"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/pull-fails"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
run local use tiny
((RC != 0)) || fail "use exited 0 although the pull failed"
expect_in "pull failed"
[[ $(<"$(state_dir)/active") == mid ]] || fail "active changed to $(<"$(state_dir)/active")"
[[ $(calls ollama) != *create* ]] || fail "a model was created after a failed pull"
rm "$SANDBOX/pull-fails"
: >"$SANDBOX/create-fails"
run local use tiny
((RC != 0)) || fail "use exited 0 although the model build failed"
expect_in "create failed"
[[ $(<"$(state_dir)/active") == mid ]] || fail "active changed to $(<"$(state_dir)/active")"
compgen -G "$(state_dir)/Modelfile.*" >/dev/null && fail "a temporary Modelfile was left behind after a failed build"
ok
cleanup_sandbox

begin "use leaves no temporary Modelfile behind when Ctrl-C or SIGTERM ends it during the build"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/create-hangs"
mkfifo "$SANDBOX/hang"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
set -m # a background job gets its own process group, as a command run from a terminal does
# A case that was itself started as a background job of a script (an agent's shell,
# a CI wrapper) has SIGINT ignored, and a process cannot take that back for its
# children. Ctrl-C at a terminal reaches the command with the default action, so the
# build is started through a program that restores it first. It becomes the
# command by exec, so $! is the command's own process and wait sees its end.
restore_sigint='import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.execvp(sys.argv[1], sys.argv[1:])'
for sig in INT TERM; do
  rm -f -- "$SANDBOX/create-started"
  python3 -I -c "$restore_sigint" "$TREE_AGENT" local use tiny >"$SANDBOX/out" 2>&1 </dev/null &
  pid=$!
  for _ in {1..100}; do
    [[ -e $SANDBOX/create-started ]] && break
    command -p sleep 0.1
  done
  [[ -e $SANDBOX/create-started ]] || fail "$sig: the build never started: $(<"$SANDBOX/out")"
  compgen -G "$(state_dir)/Modelfile.*" >/dev/null || fail "$sig: no Modelfile while the build runs, so the test proves nothing"
  kill -s "$sig" -- "-$pid"
  wait "$pid" && rc=0 || rc=$?
  ((rc != 0)) || fail "$sig: use exited 0 after it was interrupted"
  compgen -G "$(state_dir)/Modelfile.*" >/dev/null && fail "$sig: a temporary Modelfile was left behind"
  [[ $(<"$(state_dir)/active") == mid ]] || fail "$sig: active changed"
done
set +m
ok
cleanup_sandbox

begin "use asks before installing Ollama and stops on anything but yes"
make_sandbox
make_tree
set_machine 8188 32
fake_service
install_ollama
for reply in n N no '' maybe; do
  PATH=$NARROW answer "$reply" local use best
  ((RC == 1)) || fail "reply '$reply' exited $RC"
  expect_in "Install ollama-cuda with: sudo pacman -S --needed ollama-cuda"
  expect_in "Ollama is required"
done
PATH=$NARROW run local use best
((RC == 1)) || fail "end of input exited $RC"
expect_in "Ollama is required"
expect_no_calls sudo
expect_no_calls pacman
[[ ! -e $(state_dir)/active ]] || fail "active was written without Ollama"
ok
cleanup_sandbox

begin "the package to install follows the GPU: CUDA, ROCm, or plain ollama"
make_sandbox
make_tree
fake_service
install_ollama
set_machine 8188 32
PATH=$NARROW answer n local use best
expect_in "sudo pacman -S --needed ollama-cuda"
set_machine none 32
add_amd_card 0 17179869184
PATH=$NARROW answer n local use best
expect_in "sudo pacman -S --needed ollama-rocm"
set_machine none 32
rm -rf -- "$SANDBOX/drm"
PATH=$NARROW answer n local use best
expect_in "Install ollama with: sudo pacman -S --needed ollama"$'\n'
expect_no_calls sudo
ok
cleanup_sandbox

begin "a machine whose only AMD GPU is an integrated one is offered plain ollama, not ollama-rocm"
make_sandbox
make_tree
fake_service
install_ollama
set_machine none 32
add_amd_card 0 536870912
PATH=$NARROW answer n local use best
expect_in "Install ollama with: sudo pacman -S --needed ollama"$'\n'
expect_no_calls sudo
ok
cleanup_sandbox

begin "answering y, yes or YES installs the package with sudo, starts the service, then sets the model up"
for reply in y yes YES; do
  make_sandbox
  make_tree
  set_machine 8188 32
  fake_service
  install_ollama
  PATH=$NARROW answer "$reply" local use best
  ((RC == 0)) || fail "reply '$reply': use best exited $RC: $OUT"
  expect_calls sudo "pacman -S --needed ollama-cuda" "systemctl enable --now ollama.service"
  [[ $(calls ollama) == "list"$'\n'"list"$'\n'"list"$'\n'"pull tiny:1b"$'\n'"create tiny -f "* ]] \
    || fail "reply '$reply': ollama calls were: $(calls ollama)"
  [[ $(<"$(state_dir)/active") == tiny ]] || fail "reply '$reply': active is not tiny"
  [[ $OUT != *--noconfirm* ]] || fail "the install ran with --noconfirm"
  cleanup_sandbox
done
ok

begin "an ollama without the GPU runner is CPU-only: use offers the GPU package and goes on if declined"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/not-installed-ollama-cuda"
for reply in n N no '' maybe; do
  answer "$reply" local use best
  ((RC == 0)) || fail "reply '$reply' exited $RC: $OUT"
  expect_in "Install ollama-cuda with: sudo pacman -S --needed ollama-cuda"
  expect_in "Continuing without it: models will run on the CPU, slowly."
  [[ $(<"$(state_dir)/active") == tiny ]] || fail "reply '$reply': active is not tiny"
done
expect_no_calls sudo
[[ $(calls pacman) == "$(printf '%s\n' '-Q ollama-cuda' '-Q ollama-cuda' '-Q ollama-cuda' '-Q ollama-cuda' '-Q ollama-cuda')" ]] \
  || fail "pacman calls were: $(calls pacman)"
answer y local use best
((RC == 0)) || fail "reply y exited $RC: $OUT"
# The running server loaded its runners before the package came, so it has to start again.
expect_calls sudo "pacman -S --needed ollama-cuda" "systemctl restart ollama.service"
expect_in "Restarting ollama.service so it loads the GPU libraries."
answer n local use best
[[ $OUT != *"Install ollama-cuda"* ]] || fail "asked again after installing the package: $OUT"
expect_calls sudo "pacman -S --needed ollama-cuda" "systemctl restart ollama.service"
ok
cleanup_sandbox

begin "a server that was not started by the unit is not restarted for the GPU package: use says so"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/by-hand"
: >"$SANDBOX/not-installed-ollama-cuda"
answer y local use best
((RC == 0)) || fail "use exited $RC: $OUT"
expect_calls sudo "pacman -S --needed ollama-cuda"
expect_in "The Ollama that is running was not started by ollama.service: restart it to load the GPU libraries."
ok
cleanup_sandbox

begin "the GPU package to ask for follows the vendor, and a machine without a GPU asks for nothing"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/not-installed-ollama-rocm"
set_machine none 32
add_amd_card 0 17179869184
answer n local use best
expect_in "Install ollama-rocm with: sudo pacman -S --needed ollama-rocm"
expect_calls pacman "-Q ollama-rocm"
rm -rf -- "$SANDBOX/drm" "$SANDBOX/calls/pacman"
answer n local use best
((RC == 0)) || fail "use on a machine without a GPU exited $RC: $OUT"
[[ $OUT != *Install* ]] || fail "asked to install something on a machine without a GPU: $OUT"
expect_no_calls pacman
expect_no_calls sudo
ok
cleanup_sandbox

begin "without sudo or pacman an ollama that lacks the GPU runner is used as it is, and a missing ollama is refused"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
: >"$SANDBOX/not-installed-ollama-cuda"
narrow_path
rm -- "$SANDBOX/stubs/sudo"
PATH=$NARROW answer y local use best
((RC == 0)) || fail "use without sudo exited $RC: $OUT"
expect_in "sudo or pacman is missing, so ollama-cuda cannot be installed from here"
expect_in "Continuing without it"
rm -- "$SANDBOX/stubs/pacman"
rm -f -- "$SANDBOX/calls/pacman"
PATH=$NARROW answer y local use best
((RC == 0)) || fail "use without pacman exited $RC: $OUT"
[[ $OUT != *Install* && $OUT != *Continuing* ]] || fail "without pacman nothing can be checked or installed: $OUT"
expect_no_calls pacman
mv -- "$SANDBOX/stubs/ollama" "$SANDBOX/pkg/ollama"
PATH=$NARROW answer y local use best
((RC == 1)) || fail "use without ollama and without sudo exited $RC: $OUT"
expect_in "sudo or pacman is missing, so ollama-cuda cannot be installed from here"
expect_in "Ollama is required; install it with 'sudo pacman -S --needed ollama-cuda'"
ok
cleanup_sandbox

begin "use asks before a download that would leave less than 10 GB free, and stops on anything but yes"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
set_free 10999999999 # tiny is a 1 GB download: one byte short of the 1 GB plus 10 GB
for reply in n N no '' maybe; do
  answer "$reply" local use tiny
  ((RC == 1)) || fail "reply '$reply' exited $RC: $OUT"
  expect_in "tiny downloads about 1 GB, and $SANDBOX/models has 10 GB free; 10 GB should stay free."
  expect_in "keep the files of a deleted model, so removing it later may not give the space back"
  expect_in "Download anyway? [y/N]"
  expect_in "Not downloading tiny:1b"
done
run local use tiny
((RC == 1)) || fail "end of input exited $RC: $OUT"
[[ $(calls ollama) != *pull* ]] || fail "pulled without room: $(calls ollama)"
[[ $(<"$(state_dir)/active") == mid ]] || fail "active changed"
for reply in y yes YES; do
  answer "$reply" local use tiny
  ((RC == 0)) || fail "reply '$reply' exited $RC: $OUT"
  expect_in "Download anyway? [y/N]"
  [[ $(<"$(state_dir)/active") == tiny ]] || fail "reply '$reply': active is not tiny"
  printf 'mid\n' >"$(state_dir)/active"
done
[[ $(calls ollama) == *"pull tiny:1b"* ]] || fail "nothing was pulled after yes"
ok
cleanup_sandbox

begin "use does not ask when the download and the 10 GB margin fit, whatever the size of the model"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
set_free 11000000000
run local use tiny
((RC == 0)) || fail "use exited $RC: $OUT"
[[ $OUT != *"Download anyway"* ]] || fail "asked with exactly enough room: $OUT"
set_free 28999999999 # mid is a 19 GB download
answer n local use mid
((RC == 1)) || fail "use mid exited $RC with 1 byte missing: $OUT"
expect_in "mid downloads about 19 GB, and $SANDBOX/models has 28 GB free"
set_free 29000000000
run local use mid
((RC == 0)) || fail "use mid exited $RC with exactly enough room: $OUT"
ok
cleanup_sandbox

begin "use does not look at free space for a model that is already downloaded"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
set_free 1
printf '%s\n' 'NAME      ID      SIZE   MODIFIED' 'tiny:1b   ccc333  1 GB   1 hour ago' >"$SANDBOX/installed"
run local use tiny
((RC == 0)) || fail "use exited $RC: $OUT"
expect_no_calls df
[[ $(calls ollama) == *"pull tiny:1b"* ]] || fail "the pull was skipped; it is how Ollama checks the files: $(calls ollama)"
ok
cleanup_sandbox

begin "free space is read where the service keeps its models, else on /var/lib, and an unreadable figure does not stop use"
make_sandbox
make_tree
set_machine 8188 32
fake_service
: >"$SANDBOX/running"
export CACHYOS_AGENT_MODELS_DIR=$SANDBOX/not-created-yet
run local use tiny
((RC == 0)) || fail "use exited $RC: $OUT"
expect_calls df "--output=avail -B1 -- /var/lib"
rm -f -- "$SANDBOX/calls/df"
unset CACHYOS_AGENT_MODELS_DIR
run local use tiny
if [[ -d /var/lib/ollama ]]; then want=/var/lib/ollama; else want=/var/lib; fi
expect_calls df "--output=avail -B1 -- $want"
export CACHYOS_AGENT_MODELS_DIR=$SANDBOX/models
stub df 'exit 1'
run local use tiny
((RC == 0)) || fail "use with a failing df exited $RC: $OUT"
expect_in "Could not read the free space on $SANDBOX/models; not checking it."
stub df 'echo Avail; echo lots'
run local use tiny
((RC == 0)) || fail "use with an unreadable figure exited $RC: $OUT"
expect_in "Could not read the free space"
ok
cleanup_sandbox

begin "use starts the service when the server does not answer"
make_sandbox
make_tree
set_machine 8188 32
fake_service
run local use tiny
((RC == 0)) || fail "use exited $RC: $OUT"
expect_calls sudo "systemctl enable --now ollama.service"
[[ -e $SANDBOX/running ]] || fail "the service was not started"
ok
cleanup_sandbox

begin "use gives up with the journal command when the service never answers"
make_sandbox
make_tree
set_machine 8188 32
fake_service
stub ollama 'exit 1'
run local use tiny
((RC == 1)) || fail "use exited $RC"
expect_in "did not answer after 30 seconds; see: journalctl -u ollama.service"
[[ $(calls ollama) != *pull* ]] || fail "pulled without a server"
[[ ! -e $(state_dir)/active ]] || fail "active was written"
mapfile -t sleeps < <(calls sleep)
((${#sleeps[@]} == 30)) || fail "waited ${#sleeps[@]} times, not 30"
[[ ${sleeps[0]} == 1 && ${sleeps[29]} == 1 ]] || fail "the waits were not one second each: ${sleeps[*]}"
ok
cleanup_sandbox

begin "use goes on as soon as a server that comes up late answers"
make_sandbox
make_tree
set_machine 8188 32
fake_service
# list fails until it has been asked four times: the check before systemctl and
# three polls, so the fifth call answers.
# shellcheck disable=SC2016 # the stub body is a script, not a string to expand here
stub ollama '
state=${self%/stubs/*}
case $1 in
  list) n=0; if [[ -f $state/polls ]]; then n=$(<"$state/polls"); fi; echo $((n + 1)) >"$state/polls"; ((n >= 4)) || exit 1 ;;
  create) cp "$4" "$state/modelfile" ;;
esac
exit 0'
run local use tiny
((RC == 0)) || fail "use exited $RC: $OUT"
mapfile -t sleeps < <(calls sleep)
((${#sleeps[@]} == 3)) || fail "waited ${#sleeps[@]} times, not 3"
[[ $(<"$(state_dir)/active") == tiny ]] || fail "active is not tiny"
ok
cleanup_sandbox

# ---- start, stop, status, remove ---------------------------------------------------

begin "start runs the service through sudo, and does nothing when it already answers"
make_sandbox
make_tree
fake_service
run local start
((RC == 0)) || fail "start exited $RC: $OUT"
expect_calls sudo "systemctl start ollama.service"
expect_in "Ollama is running at http://127.0.0.1:11434/v1"
run local start
expect_in "already running"
expect_calls sudo "systemctl start ollama.service"
ok
cleanup_sandbox

begin "start without Ollama installed points at use"
make_sandbox
make_tree
fake_service
install_ollama
PATH=$NARROW run local start
((RC == 1)) || fail "start exited $RC"
expect_in "run: cachyos-agent local use best"
expect_no_calls sudo
ok
cleanup_sandbox

begin "stop runs the service through sudo, and does nothing when it is not running"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
run local stop
((RC == 0)) || fail "stop exited $RC: $OUT"
expect_calls sudo "systemctl stop ollama.service"
[[ ! -e $SANDBOX/running ]] || fail "the service is still running"
run local stop
expect_in "ollama.service is not running"
expect_calls sudo "systemctl stop ollama.service"
ok
cleanup_sandbox

begin "start and stop without sudo or systemctl say what is missing and leave the service alone"
make_sandbox
make_tree
fake_service
narrow_path
rm -- "$SANDBOX/stubs/sudo"
: >"$SANDBOX/running"
PATH=$NARROW run local stop
((RC == 1)) || fail "stop without sudo exited $RC: $OUT"
expect_in "sudo is needed to stop ollama.service"
[[ -e $SANDBOX/running ]] || fail "the service was stopped"
rm -f -- "$SANDBOX/running"
stub ollama 'exit 1'
PATH=$NARROW run local start
((RC == 1)) || fail "start without sudo exited $RC: $OUT"
expect_in "sudo and systemctl are needed to start ollama.service"
stub sudo 'exec "$@"'
rm -- "$SANDBOX/stubs/systemctl"
PATH=$NARROW run local stop
((RC == 1)) || fail "stop without systemctl exited $RC: $OUT"
expect_in "systemctl is needed to stop ollama.service"
ok
cleanup_sandbox

begin "status shows the service, the endpoint, the active model and what is loaded"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
printf '%s\n' 'NAME        ID      SIZE   PROCESSOR  CONTEXT  UNTIL' 'mid:latest  abc123  19 GB  100% GPU   32768    4 minutes from now' >"$SANDBOX/ps"
run local status
((RC == 0)) || fail "status exited $RC: $OUT"
expect_in "service:  active (ollama.service)"
expect_in "endpoint: http://127.0.0.1:11434/v1"
expect_in "active:   mid (mid:30b, 32K context)"
expect_in "  mid:latest  abc123  19 GB  100% GPU   32768    4 minutes from now"
printf '%s\n' 'NAME  ID  SIZE  PROCESSOR  CONTEXT  UNTIL' >"$SANDBOX/ps"
run local status
expect_in "loaded:   nothing"
ok
cleanup_sandbox

begin "status reports a stopped service, no active model and a missing Ollama without failing"
make_sandbox
make_tree
fake_service
run local status
((RC == 0)) || fail "status exited $RC"
expect_in "service:  inactive (ollama.service)"
expect_in "active:   none (set one with: cachyos-agent local use best)"
expect_in "the server is not answering (cachyos-agent local start)"
install_ollama
PATH=$NARROW run local status
((RC == 0)) || fail "status without ollama exited $RC"
expect_in "not installed (cachyos-agent local use best installs it)"
ok
cleanup_sandbox

begin "status shows an active name that is not a recipe as it is"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
mkdir -p "$(state_dir)"
printf 'my-own-model\n' >"$(state_dir)/active"
run local status
expect_in "active:   my-own-model"$'\n'
ok
cleanup_sandbox

begin "remove deletes the model and its download and clears active when it was the active one"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
printf '%s\n' 'NAME         ID      SIZE   MODIFIED' 'mid:latest   aaa111  19 GB  1 hour ago' 'mid:30b      bbb222  19 GB  1 hour ago' 'tiny:1b      ccc333  1 GB   1 hour ago' >"$SANDBOX/installed"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
run local remove mid
((RC == 0)) || fail "remove exited $RC: $OUT"
expect_in "Removed mid mid:30b"
[[ $(calls ollama) == "list"$'\n'"rm mid"$'\n'"rm mid:30b" ]] || fail "ollama calls were: $(calls ollama)"
[[ $(calls ollama) != *"rm tiny"* ]] || fail "tiny was removed too"
[[ ! -e $(state_dir)/active ]] || fail "active survived removing its model"
ok
cleanup_sandbox

begin "remove leaves active alone when another model is removed, and says when nothing is installed"
make_sandbox
make_tree
fake_service
: >"$SANDBOX/running"
printf '%s\n' 'NAME      ID      SIZE   MODIFIED' 'tiny:1b   ccc333  1 GB   1 hour ago' >"$SANDBOX/installed"
mkdir -p "$(state_dir)"
printf 'mid\n' >"$(state_dir)/active"
run local remove tiny
expect_in "Removed tiny:1b"
[[ $(<"$(state_dir)/active") == mid ]] || fail "active changed"
run local remove huge
((RC == 0)) || fail "removing an absent model exited $RC"
expect_in "huge is not installed; nothing to remove."
ok
cleanup_sandbox

begin "remove refuses an unknown recipe, a stopped service and a missing Ollama"
make_sandbox
make_tree
fake_service
run local remove nope
((RC == 1)) || fail "unknown recipe exited $RC"
expect_in "unknown recipe: nope"
run local remove tiny
((RC == 1)) || fail "stopped service exited $RC"
expect_in "start it first: cachyos-agent local start"
run local remove
((RC == 2)) || fail "no argument exited $RC"
install_ollama
PATH=$NARROW run local remove tiny
((RC == 1)) || fail "missing Ollama exited $RC"
expect_in "Ollama is not installed"
[[ $(calls ollama) != *rm* ]] || fail "rm was called"
ok
cleanup_sandbox

# ---- the dispatcher ---------------------------------------------------------------

begin "every command answers --help and -h with the usage, before it looks at the machine"
make_sandbox
set_machine 8188 32
fake_service
help=$("$AGENT" local --help)
for args in "list --help" "use --help" "use -h" "start --help" "stop -h" "status --help" "remove -h" "remove --help"; do
  # shellcheck disable=SC2086 # the words are the point
  out=$("$AGENT" local $args 2>&1 </dev/null) && rc=0 || rc=$?
  ((rc == 0)) || fail "local $args exited $rc: $out"
  [[ $out == "$help" ]] || fail "local $args did not print the usage: $out"
done
expect_no_calls nvidia-smi
expect_no_calls ollama
expect_no_calls sudo
ok
cleanup_sandbox

begin "the dispatcher lists the command, answers --help, and usage mistakes exit 2"
make_sandbox
jq -e '.commands | map(select(.route == "cachyos-agent local")) | length == 1 and (.[0].summary | length > 0)' \
  <<<"$("$AGENT" commands --json)" >/dev/null || fail "local is not in commands --json with a summary"
help=$("$AGENT" local --help)
[[ $help == *"Usage: cachyos-agent local <command> [args]"* ]] || fail "--help did not print the usage"
[[ $("$AGENT" local -h) == "$help" ]] || fail "-h differs from --help"
for args in "" "frobnicate" "list extra" "start now" "stop now" "status now"; do
  # shellcheck disable=SC2086 # the words are the point
  if "$AGENT" local $args >/dev/null 2>&1; then fail "local $args exited 0"; fi
  # shellcheck disable=SC2086
  "$AGENT" local $args >/dev/null 2>&1 && rc=0 || rc=$?
  ((rc == 2)) || fail "local $args exited $rc, not 2"
done
ok
cleanup_sandbox
