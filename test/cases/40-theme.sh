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
"$PALETTE" --help | grep -q '^Usage: cachyos-agent theme palette' || fail "no usage"
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
"$AGENT" commands --all | grep -q 'cachyos-agent theme palette' || fail "palette is not listed by commands --all"
if "$AGENT" commands | grep -q 'theme palette'; then fail "palette is not hidden"; fi
ok
cleanup_sandbox
