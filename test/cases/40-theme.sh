#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The theme commands: the template renderer in lib/theme.sh, the Plasma palette,
# the sync into Hermes, Claude Code, Pi and OpenCode, and the follow watcher.
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

# The sync honors this variable for Pi's directory and make_sandbox leaves it
# alone, so a Pi user who exports it would have this case write into their real
# agent directory. Cleared here, once, for every case below.
unset PI_CODING_AGENT_DIR

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

# ---- the Plasma palette ------------------------------------------------------

AGENT=$REPO_ROOT/bin/cachyos-agent
PALETTE=$REPO_ROOT/bin/cachyos-agent-theme-palette

# kreadconfig6 as far as the palette uses it: --file (absolute, or relative to
# XDG_CONFIG_HOME), --group, --key, --default, over a plain INI file. Cases use
# it so they pass without kconfig installed; one case below compares it with
# the real binary when there is one.
KREAD_STUB=$(
  cat <<'BODY'
file='' group='' key='' fallback=''
while (($#)); do
  case $1 in
    --file) file=$2; shift 2 ;;
    --group) group=$2; shift 2 ;;
    --key) key=$2; shift 2 ;;
    --default) fallback=$2; shift 2 ;;
    *) shift ;;
  esac
done
[[ $file == /* ]] || file=$XDG_CONFIG_HOME/$file
value=$(awk -F= -v group="[$group]" -v key="$key" '
  $0 == group { inside = 1; next }
  /^\[/ { inside = 0 }
  inside && $1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file" 2>/dev/null || true)
printf '%s\n' "${value:-$fallback}"
BODY
)

# colors_file <path> <bg> <fg> <negative> <positive> <neutral> <active> <link> <visited> <window-bg> <selection-bg> <selection-fg> [accent]
# A kdeglobals/scheme file in KDE's "r,g,b" syntax with only the groups the palette reads.
colors_file() {
  local path=$1
  mkdir -p "$(dirname "$path")"
  {
    printf '[Colors:View]\nBackgroundNormal=%s\nForegroundNormal=%s\nForegroundNegative=%s\n' "$2" "$3" "$4"
    printf 'ForegroundPositive=%s\nForegroundNeutral=%s\nForegroundActive=%s\nForegroundLink=%s\n' "$5" "$6" "$7" "$8"
    printf 'ForegroundVisited=%s\nDecorationFocus=61,174,233\n' "$9"
    printf '[Colors:Window]\nBackgroundNormal=%s\n' "${10}"
    printf '[Colors:Selection]\nBackgroundNormal=%s\nForegroundNormal=%s\n' "${11}" "${12}"
    if [[ -n ${13-} ]]; then printf '[General]\nAccentColor=%s\n' "${13}"; fi
  } >"$path"
}

# Breeze Dark's colors with a custom accent, and Breeze Light's without one.
dark_colors() { colors_file "$1" 20,22,24 252,252,252 218,68,83 39,174,96 246,116,0 61,174,233 29,153,243 155,89,182 32,35,38 61,174,233 252,252,252 146,110,214; }
light_colors() { colors_file "$1" 255,255,255 35,38,41 218,68,83 39,174,96 246,116,0 61,174,233 41,128,185 155,89,182 239,240,241 61,174,233 255,255,255; }

# Values worked out by hand, not by the palette script.
DARK_PALETTE=$'background\t#141618
foreground\t#fcfcfc
accent\t#926ed6
muted\t#9fa0a1
selection\t#3daee9
selection_background\t#3daee9
selection_foreground\t#fcfcfc
red\t#da4453
green\t#27ae60
yellow\t#f67400
blue\t#3daee9
magenta\t#9b59b6
cyan\t#1d99f3
bright_red\t#e47b86
bright_green\t#67c58f
bright_yellow\t#f89d4c
bright_blue\t#76c5ef
bright_magenta\t#b88acb
bright_cyan\t#60b7f6
bright_foreground\t#fefefe
dark_background\t#0f1112
lighter_background\t#202326
dark_foreground\t#c2c3c3
theme_type\tdark'
LIGHT_PALETTE=$'background\t#ffffff
foreground\t#232629
accent\t#3daee9
muted\t#7b7d7f
selection\t#3daee9
selection_background\t#3daee9
selection_foreground\t#ffffff
red\t#da4453
green\t#27ae60
yellow\t#f67400
blue\t#3daee9
magenta\t#9b59b6
cyan\t#2980b9
bright_red\t#a33b46
bright_green\t#26854f
bright_yellow\t#b75d0c
bright_blue\t#3585af
bright_magenta\t#774a8c
bright_cyan\t#27658e
bright_foreground\t#121315
dark_background\t#bfbfbf
lighter_background\t#eff0f1
dark_foreground\t#5a5c5f
theme_type\tlight'

begin "palette maps a dark Plasma scheme onto Omarchy's keys"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
dark_colors "$XDG_CONFIG_HOME/kdeglobals"
out=$("$PALETTE")
[[ $out == "$DARK_PALETTE" ]] || fail "dark palette differs: $(diff <(printf '%s\n' "$DARK_PALETTE") <(printf '%s\n' "$out"))"
ok
cleanup_sandbox

begin "palette maps a light scheme, taking the accent from the focus color when none is set"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
light_colors "$SANDBOX/light.colors"
out=$("$PALETTE" --file "$SANDBOX/light.colors")
[[ $out == "$LIGHT_PALETTE" ]] || fail "light palette differs: $(diff <(printf '%s\n' "$LIGHT_PALETTE") <(printf '%s\n' "$out"))"
ok
cleanup_sandbox

begin "palette drops an alpha channel and ignores values that are not colors"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
dark_colors "$SANDBOX/kdeglobals"
sed -i 's/^AccentColor=.*/AccentColor=146,110,214,255/; s/^ForegroundNeutral=.*/ForegroundNeutral=246,116,0,128/' "$SANDBOX/kdeglobals"
out=$("$PALETTE" --file "$SANDBOX/kdeglobals")
[[ $out == "$DARK_PALETTE" ]] || fail "alpha channel changed the palette"
sed -i 's/^AccentColor=.*/AccentColor=300,0,0/' "$SANDBOX/kdeglobals"
[[ $("$PALETTE" --file "$SANDBOX/kdeglobals" | grep '^accent') == $'accent\t#3daee9' ]] || fail "an out-of-range accent was not replaced by the focus color"
ok
cleanup_sandbox

begin "palette reads the scheme ColorScheme names when kdeglobals has no color groups"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$SANDBOX/share
mkdir -p "$XDG_CONFIG_HOME"
printf '[General]\nColorScheme=Mine\nAccentColor=146,110,214\n' >"$XDG_CONFIG_HOME/kdeglobals"
light_colors "$XDG_DATA_DIRS/color-schemes/Mine.colors"
dark_colors "$XDG_DATA_HOME/color-schemes/Mine.colors"
out=$("$PALETTE")
[[ $out == "$DARK_PALETTE" ]] || fail "the user's copy of the scheme did not win over the system's"
rm "$XDG_DATA_HOME/color-schemes/Mine.colors"
[[ $("$PALETTE" | grep -E '^(background|accent)') == $'background\t#ffffff\naccent\t#926ed6' ]] \
  || fail "the system copy, with the accent from kdeglobals, was not used"
unset XDG_DATA_HOME XDG_DATA_DIRS
ok
cleanup_sandbox

begin "palette falls back to BreezeDark for an unknown or hostile scheme name, and dies without one"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$SANDBOX/share
mkdir -p "$XDG_CONFIG_HOME"
dark_colors "$XDG_DATA_DIRS/color-schemes/BreezeDark.colors"
sed -i '/^\[General\]/,$d' "$XDG_DATA_DIRS/color-schemes/BreezeDark.colors"
printf '[General]\nColorScheme=NoSuchScheme\n' >"$XDG_CONFIG_HOME/kdeglobals"
[[ $("$PALETTE" | grep '^background') == $'background\t#141618' ]] || fail "an unknown scheme did not fall back to BreezeDark"
mkdir -p "$XDG_DATA_HOME/color-schemes" # so that ../decoy resolves from inside it
light_colors "$XDG_DATA_HOME/decoy.colors"
printf '[General]\nColorScheme=../decoy\n' >"$XDG_CONFIG_HOME/kdeglobals"
[[ $("$PALETTE" | grep '^background') == $'background\t#141618' ]] || fail "a scheme name with a slash was followed"
rm -r "$XDG_DATA_DIRS/color-schemes"
if out=$("$PALETTE" 2>"$SANDBOX/err"); then fail "a machine without any scheme produced a palette"; fi
[[ -z $out ]] || fail "a failed run printed a palette"
grep -q 'no color scheme found' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
unset XDG_DATA_HOME XDG_DATA_DIRS
ok
cleanup_sandbox

begin "palette names the color a scheme lacks"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
dark_colors "$SANDBOX/kdeglobals"
sed -i '/^ForegroundLink=/d' "$SANDBOX/kdeglobals"
if "$PALETTE" --file "$SANDBOX/kdeglobals" >/dev/null 2>"$SANDBOX/err"; then fail "an incomplete scheme produced a palette"; fi
grep -q 'has no color Colors:View ForegroundLink' "$SANDBOX/err" || fail "unhelpful message: $(<"$SANDBOX/err")"
ok
cleanup_sandbox

begin "palette usage: --help succeeds, bad arguments exit 2, kreadconfig6 is required"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
[[ $("$PALETTE" --help) == "Usage: cachyos-agent theme palette"* ]] || fail "no usage"
for bad in '--bogus' '--file'; do
  status=0
  "$PALETTE" $bad >/dev/null 2>&1 || status=$?
  ((status == 2)) || fail "'$bad' exited $status, not 2"
done
mkdir "$SANDBOX/tools"
for tool in dirname readlink; do ln -s "$(type -P $tool)" "$SANDBOX/tools/$tool"; done
if PATH=$SANDBOX/tools "$PALETTE" 2>"$SANDBOX/err"; then fail "ran without kreadconfig6"; fi
grep -q 'kreadconfig6 not found' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
ok
cleanup_sandbox

begin "palette reads the same values through the real kreadconfig6 as through the stub"
make_sandbox
if PATH=$BASE_PATH type -P kreadconfig6 >/dev/null; then
  dark_colors "$XDG_CONFIG_HOME/kdeglobals"
  real=$(PATH=$BASE_PATH "$PALETTE")
  [[ $real == "$DARK_PALETTE" ]] || fail "real kreadconfig6 gives a different palette"
  light_colors "$XDG_CONFIG_HOME/kdeglobals"
  real=$(PATH=$BASE_PATH "$PALETTE")
  [[ $real == "$LIGHT_PALETTE" ]] || fail "real kreadconfig6 gives a different light palette"
else
  echo "skip kreadconfig6 is not installed here, so only the stub was exercised"
fi
ok
cleanup_sandbox

begin "the dispatcher reaches the hidden palette command"
make_sandbox
stub kreadconfig6 "$KREAD_STUB"
dark_colors "$XDG_CONFIG_HOME/kdeglobals"
[[ $("$AGENT" theme palette) == "$DARK_PALETTE" ]] || fail "cachyos-agent theme palette differs from the command"
# Captured, not piped into grep -q: grep closes the pipe on its first match while
# the dispatcher is still writing, and pipefail would turn that SIGPIPE into a failure.
[[ $("$AGENT" commands --all) == *"cachyos-agent theme palette"* ]] || fail "palette is not listed by commands --all"
[[ $("$AGENT" commands) != *"theme palette"* ]] || fail "palette is not hidden"
ok
cleanup_sandbox

# ---- theme sync --------------------------------------------------------------

SYNC=$REPO_ROOT/bin/cachyos-agent-theme-sync

# sync_env: a sandbox with the dark scheme, kreadconfig6 and hermes stubs, and
# the state directory the sync renders into in $THEME.
sync_env() {
  make_sandbox
  stub kreadconfig6 "$KREAD_STUB"
  stub hermes ''
  dark_colors "$XDG_CONFIG_HOME/kdeglobals"
  THEME=$XDG_STATE_HOME/cachyos-agent/theme
}

# make_agents: the config directories of all four agents, as after each has run once.
make_agents() {
  mkdir -p "$HOME/.claude" "$HOME/.hermes/profiles/work" "$HOME/.hermes/profiles/team" "$HOME/.pi/agent" "$XDG_CONFIG_HOME/opencode"
  : >"$HOME/.hermes/config.yaml"
}

# make_tree [dir]: $TREE, a private copy of the runtime whose templates or path a case may change.
make_tree() {
  TREE=${1:-$SANDBOX/tree}
  mkdir -p "$TREE"
  cp -r "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$REPO_ROOT/data" "$REPO_ROOT/systemd" "$REPO_ROOT/VERSION" "$TREE/"
}

begin "sync renders every template with the palette into the state directory and publishes nowhere else"
sync_env
"$AGENT" theme sync >"$SANDBOX/out"
for file in hermes.yaml claude.json pi.json opencode.json palette.tsv; do
  [[ -s $THEME/$file ]] || fail "$file was not rendered"
done
if grep -rl '{{' "$THEME"; then fail "a placeholder survived rendering"; fi
for file in claude pi opencode; do jq -e . "$THEME/$file.json" >/dev/null || fail "$file.json does not parse"; done
[[ $(jq -r '.name, .base, .overrides.claude, .overrides.diffAdded, .overrides.inactive' "$THEME/claude.json") == $'CachyOS\ndark\n#926ed6\n#172d23\n#9fa0a1' ]] \
  || fail "claude.json has the wrong values"
[[ $(jq -r '.name, .vars.accent, .vars.selectedBackground, .colors.accent' "$THEME/pi.json") == $'cachyos\n#926ed6\n#302942\naccent' ]] \
  || fail "pi.json has the wrong values"
[[ $(jq -r '.theme | length, .borderActive, .diffAddedBg' "$THEME/opencode.json") == $'50\n#926ed6\n#172d23' ]] \
  || fail "opencode.json has the wrong values"
notice='# Adapted from Omarchy default/themed/hermes.yaml.tpl (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md'
[[ $(head -n 1 "$REPO_ROOT/data/themed/hermes.yaml.tpl") == "$notice" ]] || fail "the Hermes template is a port of Omarchy's without the notice in the file"
[[ $(sed -n 1,4p "$THEME/hermes.yaml") == "$notice"$'\nname: cachyos\ndescription: CachyOS Plasma color scheme\ncolors:' ]] || fail "hermes.yaml has the wrong header"
grep -qx '  ui_primary: "#926ed6"' "$THEME/hermes.yaml" || fail "hermes.yaml has the wrong accent"
if sed 1,4d "$THEME/hermes.yaml" | grep -vqE '^  [a-z_]+: "#[0-9a-f]{6}"$'; then fail "hermes.yaml has a line that is not a color"; fi
[[ ! -e $HOME/.claude && ! -e $HOME/.hermes && ! -e $HOME/.pi && ! -e $XDG_CONFIG_HOME/opencode ]] || fail "an agent directory was created without --activate"
[[ $(grep -c skipped "$SANDBOX/out") == 4 ]] || fail "each missing agent should be reported as skipped: $(<"$SANDBOX/out")"
ok
cleanup_sandbox

begin "sync follows the scheme: a light one renders a light base and new colors"
sync_env
"$SYNC" >/dev/null
light_colors "$XDG_CONFIG_HOME/kdeglobals"
"$SYNC" >/dev/null
[[ $(jq -r '.base, .overrides.claude, .overrides.diffAdded' "$THEME/claude.json") == $'light\n#3daee9\n#dff3e7' ]] || fail "claude.json did not follow the light scheme"
[[ $(jq -r '.vars.selectedBackground' "$THEME/pi.json") == '#d4edfa' ]] || fail "pi.json did not follow the light scheme"
ok
cleanup_sandbox

begin "sync publishes to existing agents, every Hermes profile included, and a second run changes nothing"
sync_env
make_agents
"$AGENT" theme sync >/dev/null
published=("$HOME/.claude/themes/cachyos.json" "$HOME/.pi/agent/themes/cachyos.json" "$XDG_CONFIG_HOME/opencode/themes/cachyos.json")
for file in "${published[@]}"; do
  case $file in */.claude/*) base=claude.json ;; */.pi/*) base=pi.json ;; *) base=opencode.json ;; esac
  cmp -s "$file" "$THEME/$base" || fail "$file differs from the rendered theme"
done
for skin in "$HOME/.hermes/skins/cachyos.yaml" "$HOME/.hermes/profiles/work/skins/cachyos.yaml" "$HOME/.hermes/profiles/team/skins/cachyos.yaml"; do
  cmp -s "$skin" "$THEME/hermes.yaml" || fail "$skin differs from the rendered skin"
done
[[ ! -e $HOME/.claude/settings.json && ! -e $HOME/.pi/agent/settings.json && ! -e $XDG_CONFIG_HOME/opencode/tui.json ]] || fail "settings were written without --activate"
[[ ! -e $SANDBOX/calls/hermes ]] || fail "hermes was run without --activate"
before=$(stat -c %i "${published[@]}" "$HOME/.hermes/skins/cachyos.yaml")
"$SYNC" >"$SANDBOX/out"
[[ $(stat -c %i "${published[@]}" "$HOME/.hermes/skins/cachyos.yaml") == "$before" ]] || fail "an unchanged theme was written again"
[[ $(grep -c unchanged "$SANDBOX/out") == 6 ]] || fail "expected six unchanged reports: $(<"$SANDBOX/out")"
light_colors "$XDG_CONFIG_HOME/kdeglobals"
"$SYNC" >/dev/null
[[ $(jq -r .base "$HOME/.claude/themes/cachyos.json") == light ]] || fail "a changed scheme was not published"
ok
cleanup_sandbox

begin "sync leaves Hermes alone until it has run, and honors the agents' own directory variables"
sync_env
mkdir -p "$HOME/.hermes"
"$SYNC" >"$SANDBOX/out"
[[ ! -e $HOME/.hermes/skins ]] || fail "a skin was published before Hermes had a config.yaml"
grep -q 'hermes: skipped' "$SANDBOX/out" || fail "no skip report for Hermes"
export HERMES_HOME=$SANDBOX/hermes-alt CLAUDE_CONFIG_DIR=$SANDBOX/claude-alt PI_CODING_AGENT_DIR=$SANDBOX/pi-alt
mkdir -p "$HERMES_HOME" "$CLAUDE_CONFIG_DIR" "$PI_CODING_AGENT_DIR"
: >"$HERMES_HOME/config.yaml"
"$SYNC" >/dev/null
for file in "$HERMES_HOME/skins/cachyos.yaml" "$CLAUDE_CONFIG_DIR/themes/cachyos.json" "$PI_CODING_AGENT_DIR/themes/cachyos.json"; do
  [[ -s $file ]] || fail "$file was not published"
done
unset HERMES_HOME CLAUDE_CONFIG_DIR PI_CODING_AGENT_DIR
ok
cleanup_sandbox

begin "sync --activate fails for a Hermes that has not run yet, as it does for a missing hermes command"
sync_env
mkdir -p "$HOME/.hermes"
status=0
"$SYNC" --activate --only hermes >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "activating without a config.yaml exited $status, not 1"
grep -q "cannot activate.*$HOME/.hermes/config.yaml" "$SANDBOX/err" || fail "no explanation on stderr: $(<"$SANDBOX/err")"
grep -q 'theme sync failed for: hermes' "$SANDBOX/err" || fail "the failure is not summarized: $(<"$SANDBOX/err")"
[[ ! -s $SANDBOX/out ]] || fail "reported success on stdout: $(<"$SANDBOX/out")"
[[ ! -e $HOME/.hermes/skins && ! -e $SANDBOX/calls/hermes ]] || fail "a skin was published or hermes was run without a config.yaml"
: >"$HOME/.hermes/config.yaml"
"$SYNC" --activate --only hermes >/dev/null
[[ -s $HOME/.hermes/skins/cachyos.yaml && $(<"$SANDBOX/calls/hermes") == $'skin\nuse\ncachyos' ]] || fail "activation did not work once Hermes had a config.yaml"
ok
cleanup_sandbox

begin "sync --activate sets each agent's theme, keeps its other settings and creates what is missing"
sync_env
mkdir -p "$HOME/.claude" "$HOME/.hermes"
: >"$HOME/.hermes/config.yaml"
printf '{"model":"opus","theme":"dark","permissions":{"allow":["Bash(ls)"]},"env":{"A":"1"}}' >"$HOME/.claude/settings.json"
"$AGENT" theme sync --activate >/dev/null
[[ $(jq -c . "$HOME/.claude/settings.json") == '{"model":"opus","theme":"custom:cachyos","permissions":{"allow":["Bash(ls)"]},"env":{"A":"1"}}' ]] \
  || fail "claude settings.json changed more than the theme: $(jq -c . "$HOME/.claude/settings.json")"
[[ $(<"$SANDBOX/calls/hermes") == $'skin\nuse\ncachyos' ]] || fail "hermes was not called with 'skin use cachyos': $(<"$SANDBOX/calls/hermes")"
[[ $(jq -c . "$HOME/.pi/agent/settings.json") == '{"theme":"cachyos"}' ]] || fail "pi settings were not created"
[[ $(jq -c . "$XDG_CONFIG_HOME/opencode/tui.json") == '{"theme":"cachyos"}' ]] || fail "opencode tui.json was not created"
for file in "$HOME/.pi/agent/themes/cachyos.json" "$XDG_CONFIG_HOME/opencode/themes/cachyos.json"; do
  [[ -s $file ]] || fail "$file was not published"
done
"$SYNC" --activate >"$SANDBOX/out"
[[ $(grep -c 'unchanged .*settings.json\|unchanged .*tui.json' "$SANDBOX/out") == 3 ]] || fail "a second --activate rewrote a setting: $(<"$SANDBOX/out")"
ok
cleanup_sandbox

begin "sync --activate keeps a symlinked settings file linked and updates other keys in tui.json"
sync_env
mkdir -p "$HOME/.claude" "$XDG_CONFIG_HOME/opencode" "$SANDBOX/dotfiles"
printf '{"theme":"dark","model":"opus"}\n' >"$SANDBOX/dotfiles/settings.json"
ln -s "$SANDBOX/dotfiles/settings.json" "$HOME/.claude/settings.json"
printf '{"keybinds":{"leader":"ctrl+x"},"theme":"tokyonight","scroll_speed":3}\n' >"$XDG_CONFIG_HOME/opencode/tui.json"
"$SYNC" --activate --only claude,opencode >/dev/null
[[ -L $HOME/.claude/settings.json ]] || fail "the symlinked settings.json was replaced by a file"
[[ $(jq -c . "$SANDBOX/dotfiles/settings.json") == '{"theme":"custom:cachyos","model":"opus"}' ]] || fail "the link's target was not updated"
[[ $(jq -c . "$XDG_CONFIG_HOME/opencode/tui.json") == '{"keybinds":{"leader":"ctrl+x"},"theme":"cachyos","scroll_speed":3}' ]] || fail "tui.json lost a key"
ok
cleanup_sandbox

begin "sync --activate does not edit a tui.jsonc and leaves a settings file that is not JSON as it was"
sync_env
mkdir -p "$XDG_CONFIG_HOME/opencode" "$HOME/.claude"
printf '{\n  // my theme\n  "theme": "nord"\n}\n' >"$XDG_CONFIG_HOME/opencode/tui.jsonc"
printf '{"theme": "dark",}\n' >"$HOME/.claude/settings.json"
status=0
"$SYNC" --activate --only claude,pi,opencode >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "a broken settings.json should fail the sync, got $status"
[[ ! -e $XDG_CONFIG_HOME/opencode/tui.json ]] || fail "tui.json was created beside a tui.jsonc"
grep -q 'not editing .*tui.jsonc' "$SANDBOX/out" || fail "no word about tui.jsonc"
[[ $(<"$HOME/.claude/settings.json") == '{"theme": "dark",}' ]] || fail "the broken settings.json was modified"
grep -q 'claude: cannot update' "$SANDBOX/err" || fail "no explanation for claude: $(<"$SANDBOX/err")"
[[ -s $HOME/.claude/themes/cachyos.json && -s $HOME/.pi/agent/themes/cachyos.json ]] || fail "one failing agent stopped the others"
grep -q 'theme sync failed for: claude' "$SANDBOX/err" || fail "the failure is not summarized"
ok
cleanup_sandbox

begin "sync --activate leaves a settings file without a JSON object as it was and says so"
sync_env
mkdir -p "$HOME/.claude" "$HOME/.pi/agent" "$XDG_CONFIG_HOME/opencode"
# jq prints nothing and exits 0 for a file of whitespace only; a null, a list or a string is no object either.
for content in $'\n' $'  \t\n\n' 'null' '[]' '"dark"' '3'; do
  for file in "$HOME/.claude/settings.json" "$HOME/.pi/agent/settings.json" "$XDG_CONFIG_HOME/opencode/tui.json"; do
    printf '%s' "$content" >"$file"
  done
  status=0
  "$SYNC" --activate --only claude,pi,opencode >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
  ((status == 1)) || fail "settings of '$content' exited $status, not 1"
  for file in "$HOME/.claude/settings.json" "$HOME/.pi/agent/settings.json" "$XDG_CONFIG_HOME/opencode/tui.json"; do
    cmp -s "$file" <(printf '%s' "$content") || fail "$file of '$content' was modified"
    grep -qF "cannot update $file" "$SANDBOX/err" || fail "no explanation for $file of '$content': $(<"$SANDBOX/err")"
  done
  if grep -q 'set theme' "$SANDBOX/out"; then fail "claimed to set a theme in '$content': $(<"$SANDBOX/out")"; fi
done
ok
cleanup_sandbox

begin "sync --activate reports a Hermes that refuses the skin, after publishing to the others"
sync_env
make_agents
stub hermes 'exit 1'
status=0
"$SYNC" --activate >/dev/null 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "a failing 'hermes skin use' should fail the sync, got $status"
grep -q "'hermes skin use cachyos' failed" "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ $(jq -r .theme "$HOME/.claude/settings.json") == custom:cachyos ]] || fail "claude was not activated after hermes failed"
ok
cleanup_sandbox

begin "sync reports a Hermes profile that cannot take the skin but still serves the others"
sync_env
make_agents
mkdir -p "$HOME/.hermes/profiles/work/skins/cachyos.yaml" # a directory where the skin belongs
status=0
"$SYNC" >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "a profile that could not be written should fail the sync, got $status"
grep -q 'cachyos.yaml is a directory' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ -s $HOME/.hermes/skins/cachyos.yaml && -s $HOME/.hermes/profiles/team/skins/cachyos.yaml && -s $HOME/.claude/themes/cachyos.json ]] \
  || fail "one profile stopped the others"
ok
cleanup_sandbox

begin "sync --only limits the work, and an unknown target exits 2 before any work"
sync_env
make_agents
"$SYNC" --only claude,pi >/dev/null
[[ -s $HOME/.claude/themes/cachyos.json && -s $HOME/.pi/agent/themes/cachyos.json ]] || fail "a requested agent was skipped"
[[ ! -e $HOME/.hermes/skins && ! -e $XDG_CONFIG_HOME/opencode/themes ]] || fail "an agent that was not requested got the theme"
[[ ! -e $THEME/hermes.yaml && ! -e $THEME/opencode.json ]] || fail "a template that was not requested was rendered"
rm -rf "$THEME"
for bad in 'claude,vim' '' ',claude' '@'; do
  status=0
  "$SYNC" --only "$bad" >/dev/null 2>&1 || status=$?
  ((status == 2)) || fail "--only '$bad' exited $status, not 2"
done
[[ ! -e $THEME ]] || fail "a rejected argument still rendered"
status=0
"$SYNC" --bogus >/dev/null 2>&1 || status=$?
((status == 2)) || fail "an unknown option exited $status, not 2"
[[ $("$SYNC" --help) == "Usage: cachyos-agent theme sync"* ]] || fail "no usage"
ok
cleanup_sandbox

begin "sync publishes nothing a template renders badly: a skin that is not plain colors, JSON that does not parse"
sync_env
make_agents
make_tree
"$TREE/bin/cachyos-agent-theme-sync" >/dev/null
good_skin=$(<"$HOME/.hermes/skins/cachyos.yaml")
dark_good=$(<"$HOME/.claude/themes/cachyos.json")
light_colors "$XDG_CONFIG_HOME/kdeglobals" # so that publishing anything now would show
for tamper in 's/^  ui_text: "{{ foreground }}"/  ui_text: "{{ foreground }}; evil"/' \
  's/^description: .*/description: CachyOS: not plain/' \
  's/^name: cachyos/name: other/' \
  's/^  background:/  Background:/' \
  's/^name: cachyos/# a comment hiding a U+2028 line break: \xe2\x80\xa8\nname: cachyos/'; do
  cp "$REPO_ROOT/data/themed/hermes.yaml.tpl" "$TREE/data/themed/hermes.yaml.tpl"
  sed -i "$tamper" "$TREE/data/themed/hermes.yaml.tpl"
  status=0
  "$TREE/bin/cachyos-agent-theme-sync" --only hermes >/dev/null 2>"$SANDBOX/err" || status=$?
  ((status == 1)) || fail "tamper '$tamper' was accepted (status $status)"
  grep -q 'not a plain color palette' "$SANDBOX/err" || fail "tamper '$tamper': $(<"$SANDBOX/err")"
  [[ $(<"$HOME/.hermes/skins/cachyos.yaml") == "$good_skin" ]] || fail "tamper '$tamper' was published"
done
cp "$REPO_ROOT/data/themed/claude.json.tpl" "$TREE/data/themed/claude.json.tpl"
sed -i 's/"base": "{{ theme_type }}",/"base": {{ theme_type }},/' "$TREE/data/themed/claude.json.tpl"
status=0
"$TREE/bin/cachyos-agent-theme-sync" --only claude >/dev/null 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "JSON that does not parse was accepted"
grep -q 'does not parse' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ $(<"$HOME/.claude/themes/cachyos.json") == "$dark_good" ]] || fail "the broken theme was published"
sed -i 's/"base": {{ theme_type }},/"base": "{{ no_such_color }}",/' "$TREE/data/themed/claude.json.tpl"
if "$TREE/bin/cachyos-agent-theme-sync" --only claude >/dev/null 2>"$SANDBOX/err"; then fail "an unknown palette key was accepted"; fi
grep -q 'unknown palette key "no_such_color"' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
ok
cleanup_sandbox

begin "sync works from a packaged layout: real files under the data root, symlinks in a bin directory"
sync_env
make_agents
make_tree "$SANDBOX/usr/share/cachyos-agent"
mkdir -p "$SANDBOX/usr/bin"
for command in "$TREE"/bin/*; do ln -s "$command" "$SANDBOX/usr/bin/${command##*/}"; done
PATH=$SANDBOX/usr/bin:$PATH "$SANDBOX/usr/bin/cachyos-agent" theme sync --activate >/dev/null
[[ $(jq -r .theme "$HOME/.claude/settings.json") == custom:cachyos && -s $HOME/.hermes/skins/cachyos.yaml ]] || fail "the symlinked command did not find its data root"
ok
cleanup_sandbox

# kdeglobals_writer: a palette command that reads the real one, then has Plasma
# write kdeglobals as the sync is running: <how> is a shell snippet run once the
# palette has been read, $1 counting the call from 1.
kdeglobals_writer() {
  stub cachyos-agent-theme-palette "$(
    cat <<BODY
dir=\${self%/stubs/*}
n=\$(grep -c '^\$' "\$dir/calls/cachyos-agent-theme-palette")
out=\$("\$CACHYOS_AGENT_BIN/cachyos-agent-theme-palette" "\$@")
$1
printf '%s\n' "\$out"
BODY
  )"
}

begin "sync goes again when kdeglobals is written while it runs, because the path unit cannot see that write"
sync_env
make_agents
light_colors "$SANDBOX/light"
# The first palette read is of the dark scheme; the light one lands just after it.
# shellcheck disable=SC2016 # the snippet is expanded by the stub, not here
kdeglobals_writer '((n == 1)) && cp "$dir/light" "$XDG_CONFIG_HOME/kdeglobals"'
"$AGENT" theme sync >"$SANDBOX/out" 2>"$SANDBOX/err"
[[ $(grep -c '^$' "$SANDBOX/calls/cachyos-agent-theme-palette") == 2 ]] || fail "the palette was read $(grep -c '^$' "$SANDBOX/calls/cachyos-agent-theme-palette") times, not twice"
for file in "$THEME/claude.json" "$HOME/.claude/themes/cachyos.json"; do
  [[ $(jq -r .base "$file") == light ]] || fail "$file still holds the scheme from before the write"
done
[[ $(jq -r '.vars.selectedBackground' "$HOME/.pi/agent/themes/cachyos.json") == '#d4edfa' ]] || fail "pi did not get the scheme that was written last"
[[ ! -s $SANDBOX/err ]] || fail "a settled sync said something on stderr: $(<"$SANDBOX/err")"
ok
cleanup_sandbox

begin "sync leaves a kdeglobals that never stops changing as a failure, after a bounded number of passes"
sync_env
make_agents
# shellcheck disable=SC2016 # the snippet is expanded by the stub, not here
kdeglobals_writer 'touch "$XDG_CONFIG_HOME/kdeglobals"'
status=0
"$SYNC" >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
((status == 1)) || fail "a kdeglobals that kept changing exited $status, not 1"
grep -q 'kdeglobals kept changing' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ $(grep -c '^$' "$SANDBOX/calls/cachyos-agent-theme-palette") == 5 ]] || fail "expected five passes, got $(grep -c '^$' "$SANDBOX/calls/cachyos-agent-theme-palette")"
[[ $(jq -r .base "$HOME/.claude/themes/cachyos.json") == dark ]] || fail "the last pass was not published"
ok
cleanup_sandbox

begin "sync does not repeat itself when kdeglobals holds still"
sync_env
make_agents
kdeglobals_writer ':'
"$SYNC" >/dev/null
[[ $(grep -c '^$' "$SANDBOX/calls/cachyos-agent-theme-palette") == 1 ]] || fail "a quiet kdeglobals took more than one pass"
ok
cleanup_sandbox

begin "sync stops and publishes nothing when there is no palette"
sync_env
make_agents
"$SYNC" >/dev/null
before=$(<"$HOME/.claude/themes/cachyos.json")
export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=$SANDBOX/share
rm "$XDG_CONFIG_HOME/kdeglobals"
status=0
"$SYNC" >"$SANDBOX/out" 2>"$SANDBOX/err" || status=$?
unset XDG_DATA_HOME XDG_DATA_DIRS
((status == 1)) || fail "sync without a palette exited $status"
grep -q 'no color scheme found' "$SANDBOX/err" || fail "the palette's reason was lost: $(<"$SANDBOX/err")"
[[ $(<"$HOME/.claude/themes/cachyos.json") == "$before" && ! -s $SANDBOX/out ]] || fail "something was published without a palette"
ok
cleanup_sandbox

begin "the theme group help lists sync and hides the palette"
make_sandbox
help=$("$AGENT" theme --help)
[[ $help == *'cachyos-agent theme sync [--activate] [--only hermes,claude,pi,opencode]'* ]] || fail "sync is missing from the group help"
[[ $help != *palette* ]] || fail "the hidden palette is listed"
ok
cleanup_sandbox

# ---- theme follow ------------------------------------------------------------

FOLLOW=$REPO_ROOT/bin/cachyos-agent-theme-follow

# follow_env: a systemctl that remembers whether the path unit was enabled, and an
# empty directory standing in for /usr/lib/systemd/user (a checkout: no units there).
follow_env() {
  make_sandbox
  stub systemctl "$(
    cat <<'BODY'
dir=${self%/stubs/*}
[[ $1 == --user ]] && shift
case $1 in
  enable) touch "$dir/watching" ;;
  disable) rm -f "$dir/watching" ;;
  is-enabled) if [[ -f $dir/watching ]]; then echo enabled; else echo disabled; exit 1; fi ;;
  is-active) if [[ -f $dir/watching ]]; then echo active; else echo inactive; exit 3; fi ;;
  cat) [[ -f $XDG_CONFIG_HOME/systemd/user/$2 || -f $CACHYOS_AGENT_SYSTEM_UNIT_DIR/$2 ]] ;;
esac
BODY
  )"
  export CACHYOS_AGENT_SYSTEM_UNIT_DIR=$SANDBOX/system-units
  mkdir -p "$CACHYOS_AGENT_SYSTEM_UNIT_DIR"
  UNITS=$XDG_CONFIG_HOME/systemd/user
}

end_follow_env() {
  ok
  unset CACHYOS_AGENT_SYSTEM_UNIT_DIR
  cleanup_sandbox
}

begin "the shipped units watch kdeglobals through %E and run the sync once per change"
make_sandbox
path_unit=$REPO_ROOT/systemd/user/cachyos-agent-theme-sync.path
service_unit=$REPO_ROOT/systemd/user/cachyos-agent-theme-sync.service
grep -qx 'PathModified=%E/kdeglobals' "$path_unit" || fail "the path unit does not watch %E/kdeglobals"
grep -qx 'WantedBy=default.target' "$path_unit" || fail "the path unit cannot be enabled"
grep -qx 'Type=oneshot' "$service_unit" || fail "the service is not oneshot"
grep -qx 'StartLimitIntervalSec=0' "$service_unit" || fail "a burst of kdeglobals writes could stop the watcher"
grep -qx 'TimeoutStartSec=60' "$service_unit" || fail "a hung sync would leave the path unit unwatched for good"
[[ $(grep '^ExecStart=' "$service_unit") == 'ExecStart=/usr/bin/cachyos-agent-theme-sync' ]] || fail "the service does not run the packaged command"
[[ -x $REPO_ROOT/bin/cachyos-agent-theme-sync ]] || fail "the command the service runs is not shipped"
if type -P systemd-analyze >/dev/null; then
  mkdir "$SANDBOX/units"
  cp "$path_unit" "$service_unit" "$SANDBOX/units/"
  sed -i "s|=/usr/bin/|=$REPO_ROOT/bin/|" "$SANDBOX/units/cachyos-agent-theme-sync.service"
  systemd-analyze --user verify "$SANDBOX"/units/cachyos-agent-theme-sync.{path,service} >"$SANDBOX/verify" 2>&1 \
    || fail "systemd-analyze rejects the units: $(<"$SANDBOX/verify")"
fi
ok
cleanup_sandbox

begin "follow on from a checkout generates units for the checkout, enables the path unit, and status and off undo it"
follow_env
"$AGENT" theme follow on >/dev/null
for unit in cachyos-agent-theme-sync.path cachyos-agent-theme-sync.service; do
  [[ -s $UNITS/$unit ]] || fail "$unit was not generated"
  [[ $(head -n 1 "$UNITS/$unit") == '# Generated by cachyos-agent theme follow'* ]] || fail "$unit has no generated marker"
done
[[ $(grep '^ExecStart=' "$UNITS/cachyos-agent-theme-sync.service") == "ExecStart=$REPO_ROOT/bin/cachyos-agent-theme-sync" ]] || fail "the service does not run this checkout's command"
grep -qx 'PathModified=%E/kdeglobals' "$UNITS/cachyos-agent-theme-sync.path" || fail "the generated path unit lost its watch"
if grep -q '/usr/bin/' "$UNITS"/*; then fail "a generated unit still names /usr/bin"; fi
[[ $(<"$SANDBOX/calls/systemctl") == $'--user\ndaemon-reload\n\n--user\nenable\n--now\ncachyos-agent-theme-sync.path' ]] \
  || fail "unexpected systemctl calls: $(<"$SANDBOX/calls/systemctl")"
[[ $("$AGENT" theme follow status) == 'theme follow: on (enabled, active)' ]] || fail "status after on: $("$AGENT" theme follow status)"
[[ $("$AGENT" theme follow) == "$("$AGENT" theme follow status)" ]] || fail "status is not the default"
"$AGENT" theme follow on >/dev/null || fail "turning on twice failed"
"$AGENT" theme follow off >/dev/null
[[ ! -e $UNITS/cachyos-agent-theme-sync.path && ! -e $UNITS/cachyos-agent-theme-sync.service ]] || fail "off left the generated units"
[[ $("$AGENT" theme follow status) == 'theme follow: off (disabled, inactive)' ]] || fail "status after off: $("$AGENT" theme follow status)"
grep -qx 'disable' "$SANDBOX/calls/systemctl" || fail "off did not disable the path unit"
end_follow_env

begin "follow off with nothing installed succeeds without touching systemd units"
follow_env
"$FOLLOW" off >"$SANDBOX/out"
[[ $(<"$SANDBOX/out") == 'theme follow: off' ]] || fail "unexpected output: $(<"$SANDBOX/out")"
if grep -qx 'disable' "$SANDBOX/calls/systemctl"; then fail "disabled a unit that does not exist"; fi
[[ $("$FOLLOW" status) == 'theme follow: off (disabled, inactive)' ]] || fail "unexpected status: $("$FOLLOW" status)"
end_follow_env

begin "follow on with the units packaged generates nothing and drops a stale generated copy"
follow_env
cp "$REPO_ROOT"/systemd/user/* "$CACHYOS_AGENT_SYSTEM_UNIT_DIR/"
mkdir -p "$UNITS"
printf '# Generated by cachyos-agent theme follow from /old/checkout\n[Path]\n' >"$UNITS/cachyos-agent-theme-sync.path"
printf '[Unit]\nDescription=mine\n' >"$UNITS/cachyos-agent-theme-sync.service"
"$FOLLOW" on >/dev/null
[[ ! -e $UNITS/cachyos-agent-theme-sync.path ]] || fail "a stale generated unit would shadow the packaged one"
[[ -s $UNITS/cachyos-agent-theme-sync.service ]] || fail "a unit someone wrote was removed"
grep -qx 'enable' "$SANDBOX/calls/systemctl" || fail "the packaged path unit was not enabled"
end_follow_env

begin "follow on refuses to replace a unit it did not generate and a checkout path that needs escaping"
follow_env
mkdir -p "$UNITS"
printf '[Unit]\nDescription=mine\n' >"$UNITS/cachyos-agent-theme-sync.service"
if "$FOLLOW" on >/dev/null 2>"$SANDBOX/err"; then fail "overwrote a unit it did not generate"; fi
grep -q 'was not generated by this command' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ $(<"$UNITS/cachyos-agent-theme-sync.service") == $'[Unit]\nDescription=mine' && ! -e $UNITS/cachyos-agent-theme-sync.path ]] || fail "units were written anyway"
rm "$UNITS/cachyos-agent-theme-sync.service"
make_tree "$SANDBOX/my tree"
if "$TREE/bin/cachyos-agent-theme-follow" on >/dev/null 2>"$SANDBOX/err"; then fail "generated units for a path with a space"; fi
grep -q 'needs escaping' "$SANDBOX/err" || fail "no explanation: $(<"$SANDBOX/err")"
[[ ! -e $UNITS/cachyos-agent-theme-sync.path && ! -e $SANDBOX/calls/systemctl ]] || fail "something was done before the path was refused"
end_follow_env

begin "follow usage: --help succeeds, anything else exits 2"
make_sandbox
[[ $("$FOLLOW" --help) == "Usage: cachyos-agent theme follow"* ]] || fail "no usage"
for bad in 'bogus' 'on off' '--bogus'; do
  read -ra args <<<"$bad"
  status=0
  "$FOLLOW" "${args[@]}" >/dev/null 2>&1 || status=$?
  ((status == 2)) || fail "'$bad' exited $status, not 2"
done
ok
cleanup_sandbox

begin "the theme group help lists sync and follow"
make_sandbox
help=$("$AGENT" theme --help)
[[ $help == *'cachyos-agent theme follow [on|off|status]'* ]] || fail "follow is missing from the group help"
[[ $help == *'cachyos-agent theme sync'* ]] || fail "sync is missing from the group help"
ok
cleanup_sandbox
