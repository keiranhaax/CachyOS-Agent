#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The Plasma widget in plasmoid/org.cachyos.agent: its package files, the QML
# it is written in, the JavaScript that shapes usage records for it, and the
# whole path from `cachyos-agent usage --json` to what it shows. There is no
# desktop here, so what runs does so under qml6 with the offscreen platform:
# records.js alone, and main.qml against test/plasmoid/stubs, which replace only
# the PlasmoidItem and Plasmoid that plasmashell provides. The data engine, the
# Plasma components and Kirigami are the installed ones. A check whose tool or
# Qt module is missing is reported UNVERIFIED and does not fail the case.
# The jq programs and the stub's body are single-quoted so that their $ reaches
# jq and the stub as written.
# shellcheck disable=SC2016
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

PKG=$REPO_ROOT/plasmoid/org.cachyos.agent
HARNESS=$REPO_ROOT/test/plasmoid
QML_DIR=/usr/lib/qt6/qml
ENGINE=/usr/lib/qt6/plugins/plasma5support/dataengine/plasma_engine_executable.so
QML_FILES=("$PKG"/contents/ui/*.qml "$PKG"/contents/config/config.qml)

unverified() {
  printf 'UNVERIFIED %s: %s\n' "$1" "$2"
}

# check <json> <jq filter> <what>: fails unless the filter is true for the json.
check() {
  jq -e "$2" <<<"$1" >/dev/null 2>&1 || fail "$3: $1"
}

# qml_json <qml6 args...>: run qml6 headless and print the JSON on the line the
# harness logs. The whole log stays in $QML_LOG for the checks that read it.
qml_json() {
  local status=0
  QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 60 qml6 "$@" >"$QML_LOG" 2>&1 || status=$?
  if ((status != 0)) || ! grep -q '^qml: RESULT ' "$QML_LOG"; then
    fail "qml6 exited $status without a result: $(head -c 800 "$QML_LOG")"
    echo null
    return 0
  fi
  sed -n 's/^qml: RESULT //p' "$QML_LOG"
}

# records <function name as JSON> [argument as JSON...]: call a function of records.js.
records() {
  qml_json "$HARNESS/records.qml" -- "$(jq -nc '$ARGS.positional | map(fromjson)' --args "$@")"
}

# app <action> <expected>: run the widget and print what it shows. The action is
# "dump" or the text of a button to click, and <expected> what the agents must
# mention before the page is read after a click.
app() {
  qml_json -I "$HARNESS/stubs" "$HARNESS/app.qml" -- "$PKG/contents/ui/main.qml" "$1" "$2"
}

# calls_of <stub>: the calls the stub recorded, one per line.
calls_of() {
  awk 'BEGIN { RS = ""; FS = "\n"; OFS = " " } { $1 = $1; print }' "$SANDBOX/calls/$1"
}

# No error QML reports about our files may pass unnoticed in a log.
qml_log_is_clean() {
  ! grep -E 'TypeError|ReferenceError|SyntaxError|Unable to assign|Cannot assign|Cannot read|Binding loop|is not a type|is not installed|Required property|org.cachyos.agent' "$QML_LOG"
}

# records_json <now in epoch seconds>: the usage records every check below reads,
# with the times that matter given relative to <now>.
records_json() {
  local now=$1 iso='+%Y-%m-%dT%H:%M:%S'
  sed -e "s/@SESSION@/$(date -u -d "@$((now + 7830))" "$iso").123456+00:00/" \
    -e "s/@WEEK@/$(date -u -d "@$((now + 3 * 86400 + 4 * 3600 + 30))" "$iso")Z/" \
    -e "s/@ELAPSED@/$(date -u -d "@$((now - 60))" "$iso")Z/" \
    -e "s/@OLD@/$(date -u -d "@$((now - 2 * 86400 - 3 * 3600 - 300))" "$iso").654321+00:00/" \
    -e "s/@FETCHED2H@/$(((now - 7200) * 1000))/" \
    -e "s/@FETCHED3H@/$(((now - 10800) * 1000))/" <<'EOF'
[
  {
    "id": "claude", "name": "Claude Code", "ready": true, "tierLabel": "pro",
    "limits": [
      {"label": "Session (5-hour)", "percent": 0.42, "resetsAt": "@SESSION@"},
      {"label": "Weekly (7-day)", "percent": 0.95, "resetsAt": "@WEEK@"},
      {"label": "Fable Weekly", "title": "Fable Weekly", "percent": 0.1, "resetsAt": "@ELAPSED@"}
    ],
    "todayTotalTokens": 1234567,
    "recentDays": [
      {"date": "2026-10-27", "messageCount": 100000}, {"date": "2026-10-28", "messageCount": 200000},
      {"date": "2026-10-29", "messageCount": 300000}, {"date": "2026-10-30", "messageCount": 400000},
      {"date": "2026-10-31", "messageCount": 500000}, {"date": "2026-11-01", "messageCount": 600000},
      {"date": "2026-11-02", "messageCount": 1234567}
    ],
    "accounts": [
      {"id": ":primary", "label": "Personal", "plan": "pro", "active": true, "stale": false, "fetchedAt": 0,
       "limits": [{"label": "Session (5-hour)", "percent": 0.42, "resetsAt": "@SESSION@"}],
       "usageStatusText": "", "authHelpText": ""},
      {"id": "work", "label": "Work", "plan": "max", "active": false, "stale": true, "fetchedAt": @FETCHED3H@,
       "limits": [{"label": "Session (5-hour)", "percent": 0.8, "resetsAt": ""}],
       "usageStatusText": "Sign-in expired", "authHelpText": "Run `claude auth login`."}
    ]
  },
  {
    "id": "openrouter", "name": "OpenRouter", "ready": true, "tierLabel": "Prepaid",
    "balance": {"remaining": 3.5, "funded": 20, "spent": 16.5, "currency": "USD", "estimated": false}
  },
  {
    "id": "deepseek", "name": "DeepSeek", "ready": true, "tierLabel": "Prepaid",
    "balance": {"remaining": 1, "funded": 20, "spent": 19, "currency": "CNY", "estimated": true}
  },
  {
    "id": "fireworks", "name": "Fireworks", "ready": true, "tierLabel": "Prepaid", "updatedAt": "@OLD@",
    "balance": {"remaining": 2, "currency": "EUR"}
  },
  {
    "id": "codex", "name": "Codex", "ready": true, "tierLabel": "plus",
    "limits": [{"label": "Session", "percent": 0.5, "resetsAt": ""}],
    "limitsStale": true, "limitsFetchedAt": @FETCHED2H@,
    "usageStatusText": "Limits paused", "authHelpText": "Start Codex to see its limits."
  },
  {
    "id": "grok", "name": "Grok", "ready": false, "tierLabel": "", "limits": [],
    "todayTotalTokens": 0, "recentDays": []
  },
  {
    "id": "hermes", "name": "Hermes", "ready": true, "tierLabel": "", "limits": [],
    "usageStatusText": "", "authHelpText": "Run `hermes login` to sign in.",
    "todayTotalTokens": 500, "recentDays": [{"date": "2026-11-02", "messageCount": 500}]
  },
  "not a record", null, [],
  {
    "id": "evil", "name": "<b>Evil</b><img src=x>", "ready": true,
    "limits": [
      {"label": "<i>nan</i>", "percent": "nan"},
      {"label": "over", "percent": 7, "resetsAt": "garbage"},
      null, 5
    ],
    "balance": {"remaining": -1}, "recentDays": "zzz", "todayTotalTokens": "1e400",
    "limitsStale": true, "limitsFetchedAt": 99999999999999
  }
]
EOF
}

# ---- package files -------------------------------------------------------------

begin "metadata.json is a Plasma 6 applet package for org.cachyos.agent"
make_sandbox
meta=$(<"$PKG/metadata.json")
check "$meta" '.KPackageStructure == "Plasma/Applet" and .["X-Plasma-API-Minimum-Version"] == "6.0"' "wrong package structure or API version"
check "$meta" '.KPlugin | .Id == "org.cachyos.agent" and .Name == "CachyOS Agents" and .Category == "System Information"
               and .License == "GPL-3.0-only" and (.Description | length > 0) and (.Icon | length > 0)
               and (.Authors | length > 0) and all(.Authors[]; (.Name | length > 0) and (.Email | length > 0))' "missing or wrong KPlugin keys"
[[ $(ls "$REPO_ROOT/plasmoid") == org.cachyos.agent ]] || fail "plasmoid/ must hold only the package, named by its Id, or the PKGBUILD installs strays"
[[ -f $PKG/contents/ui/main.qml ]] || fail "Plasma starts contents/ui/main.qml and it is missing"
ok
cleanup_sandbox

begin "every icon the widget names is in the Breeze theme"
make_sandbox
if [[ -d /usr/share/icons/breeze ]]; then
  icons=$(
    jq -r '.KPlugin.Icon' "$PKG/metadata.json"
    grep -hoE '(icon\.name|icon|source): "[a-z][a-z0-9-]*"' "${QML_FILES[@]}" | sed -E 's/.*"(.*)"/\1/'
  )
  [[ -n $icons ]] || fail "found no icon names to check"
  while IFS= read -r icon; do
    [[ -n $(find /usr/share/icons/breeze -name "$icon.svg" -print -quit) ]] || fail "icon $icon is not in the Breeze theme"
  done <<<"$icons"
else
  unverified "icons" "/usr/share/icons/breeze is not installed"
fi
ok
cleanup_sandbox

begin "the refresh interval has a default and a settings page that edits it"
make_sandbox
python3 -I - "$PKG/contents/config/main.xml" <<'PY' || fail "main.xml does not define refreshIntervalSec as an Int defaulting to 900"
import sys
import xml.etree.ElementTree as ET

ns = {"k": "http://www.kde.org/standards/kcfg/1.0"}
entry = ET.parse(sys.argv[1]).getroot().find(".//k:entry[@name='refreshIntervalSec']", ns)
assert entry is not None and entry.get("type") == "Int"
assert entry.findtext("k:default", namespaces=ns) == "900"
PY
grep -q 'cfg_refreshIntervalSec' "$PKG/contents/ui/configGeneral.qml" || fail "the settings page does not bind cfg_refreshIntervalSec"
grep -q 'source: "configGeneral.qml"' "$PKG/contents/config/config.qml" || fail "config.qml does not offer the settings page"
grep -q 'Plasmoid.configuration.refreshIntervalSec' "$PKG/contents/ui/main.qml" || fail "main.qml does not read the setting"
ok
cleanup_sandbox

# ---- QML sources ---------------------------------------------------------------

begin "every QML import names an installed module or an existing file"
make_sandbox
for file in "${QML_FILES[@]}"; do
  while IFS= read -r line; do
    if [[ $line =~ ^import[[:space:]]+\"([^\"]+)\" ]]; then
      [[ -f $(dirname "$file")/${BASH_REMATCH[1]} ]] || fail "${file##*/} imports ${BASH_REMATCH[1]}, which does not exist"
    elif [[ $line =~ ^import[[:space:]]+([A-Za-z0-9_.]+) ]]; then
      module=${BASH_REMATCH[1]}
      if [[ -d $QML_DIR ]]; then
        [[ -f $QML_DIR/${module//.//}/qmldir ]] || fail "${file##*/} imports $module, which is not under $QML_DIR"
      fi
    fi
  done < <(grep -E '^import ' "$file")
done
[[ -d $QML_DIR ]] || unverified "QML module imports" "$QML_DIR is not installed"
ok
cleanup_sandbox

begin "every label, heading and text item shows plain text"
make_sandbox
# Agent names and help texts come from files on disk, so none may be read as markup.
for file in "${QML_FILES[@]}"; do
  missing=$(awk '
    function braces(s,   opened, closed) { opened = gsub(/[{]/, "&", s); closed = gsub(/[}]/, "&", s); return opened - closed }
    inside == 0 && /(Label|Heading|Text)[[:space:]]*\{[[:space:]]*$/ { inside = 1; depth = 0; plain = 0; start = FNR }
    inside == 1 {
      if ($0 ~ /textFormat: Text\.PlainText/) plain = 1
      depth += braces($0)
      if (depth <= 0) { if (!plain) print "line " start; inside = 0 }
    }' "$file")
  [[ -z $missing ]] || fail "${file##*/}: text without textFormat: Text.PlainText at $missing"
done
grep -q 'toolTipTextFormat: Text.PlainText' "$PKG/contents/ui/main.qml" || fail "the tooltip is not plain text"
ok
cleanup_sandbox

begin "qmllint accepts the QML"
make_sandbox
qmllint=$(command -v qmllint || ls /usr/lib/qt6/bin/qmllint 2>/dev/null || true)
if [[ -n $qmllint && -d $QML_DIR/org/kde/plasma/plasmoid ]]; then
  "$qmllint" --max-warnings 0 "${QML_FILES[@]}" >"$SANDBOX/lint.log" 2>&1 || fail "qmllint: $(head -c 800 "$SANDBOX/lint.log")"
else
  unverified "QML lint" "qmllint or the Plasma QML modules are not installed"
fi
ok
cleanup_sandbox

# ---- records.js ----------------------------------------------------------------

if command -v qml6 >/dev/null; then
  NOW=1793642400000 # 2026-11-02T18:00:00Z

  begin "records.js formats durations, reset times and token counts"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  [[ $(records '"duration"' 1000) == '"1m"' ]] || fail "a few seconds are not rounded up to 1m"
  [[ $(records '"duration"' 7800000) == '"2h 10m"' ]] || fail "2h 10m"
  [[ $(records '"duration"' 273600000) == '"3d 4h"' ]] || fail "3d 4h"
  [[ $(records '"resetText"' 0 1000) == '""' ]] || fail "a window with no reset time should say nothing"
  [[ $(records '"resetText"' 7801000 1000) == '"resets in 2h 10m"' ]] || fail "resets in 2h 10m"
  [[ $(records '"resetText"' 500 1000) == '"resetting"' ]] || fail "a reset time that has passed should say resetting"
  [[ $(records '"tokens"' 12) == '"12"' && $(records '"tokens"' 1234) == '"1.2K"' ]] || fail "small token counts"
  [[ $(records '"tokens"' 999950) == '"1.0M"' ]] || fail "999950 tokens should read 1.0M, not 1000.0K"
  [[ $(records '"tokens"' 2500000000) == '"2.5B"' ]] || fail "billions of tokens"
  ok
  cleanup_sandbox

  begin "records.js load reports a failed or garbled usage command in one line"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  out=$(records '"load"' 127 '""' '"sh: line 1: cachyos-agent: command not found\n"' "$NOW")
  check "$out" '.agents == [] and .error == "cachyos-agent usage --json failed: sh: line 1: cachyos-agent: command not found"' "a failed command"
  out=$(records '"load"' 3 '""' '""' "$NOW")
  check "$out" '.agents == [] and .error == "cachyos-agent usage --json failed (exit 3)"' "a failed command that said nothing"
  out=$(records '"load"' 0 '"not json"' '""' "$NOW")
  check "$out" '.agents == [] and .error == "cachyos-agent usage --json did not print a JSON array"' "output that is not JSON"
  out=$(records '"load"' 0 '"{}"' '""' "$NOW")
  check "$out" '.agents == [] and (.error | endswith("did not print a JSON array"))' "a JSON object instead of an array"
  out=$(records '"load"' 0 '"[]"' '""' "$NOW")
  check "$out" '.agents == [] and .error == ""' "no records is not an error"
  ok
  cleanup_sandbox

  begin "records.js reads reset times as the collectors do, in any time zone"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  # One hour from NOW, written the ways a collector passes a service's reset
  # time through: the collectors and `cachyos-agent usage` read a time with no
  # offset as UTC, and Python's fromisoformat also takes the basic form.
  soon=$((NOW / 1000 + 3600))
  stamp() { date -u -d "@$1" "+$2"; }
  windows=$(jq -nc --arg a "$(stamp "$soon" %Y-%m-%dT%H:%M:%S)" --arg b "$(stamp "$soon" %Y%m%dT%H%M%SZ)" \
    --arg c "$(stamp "$((soon + 19800))" %Y-%m-%dT%H:%M:%S.123456)+05:30" --arg d "$(stamp "$((soon - 7200))" %Y-%m-%dT%H:%M:%S)-0200" \
    --arg e "$(stamp "$soon" '%Y-%m-%d %H:%M:%S')Z" \
    '[$a, $b, $c, $d, $e] | map({label: "Session", percent: 0.95, resetsAt: .})')
  record=$(jq -nc --argjson limits "$windows" '[{id: "x", name: "X", ready: true, tierLabel: "pro", limits: $limits}]')
  for zone in UTC Europe/Madrid America/New_York; do
    out=$(TZ=$zone records '"load"' 0 "$(jq -Rs . <<<"$record")" '""' "$NOW")
    check "$out" '[.agents[0].limits[] | [.percentText, .resetMs]] == [range(5) | ["95%", '$((soon * 1000))' + (if . == 2 then 123 else 0 end)]]' \
      "reset times with no offset, in the basic form, with an offset or with a fraction, read in $zone"
  done
  out=$(records '"load"' 0 "$(jq -Rs . <<<'[{"id": "x", "name": "X", "ready": true, "limits": [{"label": "Session", "percent": 0.5, "resetsAt": "20261103"}, {"label": "Weekly", "percent": 0.5, "resetsAt": "2026-13-45T25:61:61Z"}]}]')" '""' "$NOW")
  check "$out" '[.agents[0].limits[] | [.percentText, .resetMs]] == [["50%", 0], ["50%", 0]]' "a date or a time that is not one has no countdown"
  ok
  cleanup_sandbox

  begin "records.js says how old a record is once nothing has refreshed it for an hour"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  # `cachyos-agent usage` flags a record older than an hour; the widget never
  # runs `usage update` itself, so it must too, or days-old numbers read as current.
  ago() { stamp "$((NOW / 1000 - $1))" %Y-%m-%dT%H:%M:%S.000000+00:00; }
  record=$(jq -nc --arg old "$(ago $((2 * 86400 + 3 * 3600 + 120)))" --arg hour "$(ago 3600)" --arg recent "$(ago 3599)" \
    --arg future "$(ago -60)" --arg naive "$(stamp "$((NOW / 1000 - 7200))" %Y-%m-%dT%H:%M:%S)" '
    def balance: {remaining: 5, funded: 10, spent: 5, currency: "USD"};
    [{id: "a", name: "Old", ready: true, balance: balance, updatedAt: $old},
     {id: "b", name: "An hour", ready: true, balance: balance, updatedAt: $hour},
     {id: "c", name: "Recent", ready: true, balance: balance, updatedAt: $recent},
     {id: "d", name: "Future", ready: true, balance: balance, updatedAt: $future},
     {id: "e", name: "Naive", ready: true, balance: balance, updatedAt: $naive},
     {id: "f", name: "Garbled", ready: true, balance: balance, updatedAt: "yesterday"},
     {id: "g", name: "Unwritten", ready: true, balance: balance},
     {id: "h", name: "Stale too", ready: true, balance: balance, updatedAt: $old, limitsStale: true, limitsFetchedAt: 0,
      usageStatusText: "Sign-in expired", authHelpText: "Run `h login`."}]')
  out=$(records '"load"' 0 "$(jq -Rs . <<<"$record")" '""' "$NOW")
  check "$out" '[.agents[] | [.name, .notes]] == [["Old", ["Updated 2d 3h ago"]], ["An hour", ["Updated 1h 0m ago"]], ["Recent", []], ["Future", []],
                  ["Naive", ["Updated 2h 0m ago"]], ["Garbled", []], ["Unwritten", []],
                  ["Stale too", ["Updated 2d 3h ago", "Sign-in expired", "Run `h login`.", "Limits may be out of date"]]]' \
    "only a record at least an hour old says how old it is, before anything else"
  ok
  cleanup_sandbox

  begin "records.js load turns usage records into what the widget draws"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  records_json $((NOW / 1000)) >"$SANDBOX/records.json"
  out=$(records '"load"' 0 "$(jq -Rs . "$SANDBOX/records.json")" '""' "$NOW")
  check "$out" '.error == "" and ([.agents[].name] == ["Claude Code", "OpenRouter", "DeepSeek", "Fireworks", "Codex", "Hermes", "<b>Evil</b><img src=x>"])' \
    "agents should be the used ones, in file order, with markup left alone and non-records dropped"
  check "$out" '.agents[0] | .plan == "Pro" and .tokensText == "Tokens: 1.2M today, 3.3M this week" and .notes == []
                and ([.limits[] | [.title, .percentText, .high]] == [["Session (5-hour)", "42%", false], ["Weekly (7-day)", "95%", true], ["Fable Weekly", "0%", false]])' \
    "Claude Code: plan, tokens, limits (an elapsed window reads 0%)"
  [[ $(records '"resetText"' "$(jq '.agents[0].limits[0].resetMs' <<<"$out")" "$NOW") == '"resets in 2h 10m"' ]] || fail "the session reset time"
  [[ $(records '"resetText"' "$(jq '.agents[0].limits[1].resetMs' <<<"$out")" "$NOW") == '"resets in 3d 4h"' ]] || fail "the weekly reset time"
  check "$out" '.agents[0].limits[2].resetMs == 0' "an elapsed window has no reset time"
  check "$out" '.agents[0].accounts | map([.name, .plan, .active, (.limits | length), .notes]) ==
                [["Personal", "Pro", true, 1, []], ["Work", "Max", false, 1, ["Sign-in expired", "Run `claude auth login`.", "Limits last checked 3h 0m ago"]]]' \
    "accounts and their own notes"
  check "$out" '.agents[1] | .plan == "Prepaid" and .limits == [] and .balance == {remainingText: "$3.50 left", detailText: "$16.50 spent of $20.00", fraction: 0.175, low: false}' \
    "a prepaid balance"
  check "$out" '.agents[2].balance | .remainingText == "CNY 1.00 left" and .detailText == "CNY 19.00 spent of CNY 20.00 (estimated)" and .low == true' \
    "a low, estimated balance in another currency"
  check "$out" '.agents[3] | .balance == {remainingText: "€2.00 left", detailText: "", fraction: -1, low: false} and .notes == ["Updated 2d 3h ago"]' \
    "a balance with no funding figure has nothing to measure against, and a record two days old says so"
  check "$out" '.agents[4] | .plan == "Plus" and .notes == ["Limits paused", "Start Codex to see its limits.", "Limits last checked 2h 0m ago"]' \
    "stale limits say why and how old"
  check "$out" '.agents[5] | .tokensText == "Tokens: 500 today, 500 this week" and .limits == [] and .balance == null and .notes == []' \
    "an agent with only local tokens, and a sign-in hint that stays hidden while all is well"
  check "$out" '.agents[6] | .plan == "" and .tokensText == "" and .balance == null and .accounts == []
                and ([.limits[] | [.title, .percentText, .resetMs, .high]] == [["over", "100%", 0, true]])
                and .notes == ["Limits may be out of date"]' \
    "hostile values are dropped or clamped, and a fetch time from the future is not believed"
  out=$(records '"summary"' "$(jq -c .agents <<<"$out")")
  [[ $out == '"Claude Code 95%, Codex 50%, <b>Evil</b><img src=x> 100%"' ]] || fail "the tooltip summary: $out"
  ok
  cleanup_sandbox
else
  unverified "records.js" "qml6 is not installed, so no JavaScript engine is available"
fi

# ---- the widget end to end -----------------------------------------------------

if command -v qml6 >/dev/null && [[ -f $ENGINE && -d $QML_DIR/org/kde/plasma/plasma5support && -d $QML_DIR/org/kde/plasma/extras ]]; then
  # What the widget runs is stubbed at the command line: the stub cachyos-agent
  # prints $FIXTURE for `usage --json` and notes `usage update` in $MARKER.
  stub_agent() {
    stub cachyos-agent '
case "$1 ${2-}" in
  "usage --json")
    if [[ -e $MARKER && -n ${FIXTURE_AFTER-} ]]; then cat "$FIXTURE_AFTER"; else cat "$FIXTURE"; fi ;;
  "usage update")
    : >"$MARKER"
    [[ -z ${UPDATE_STDERR-} ]] || echo "$UPDATE_STDERR" >&2
    exit "${UPDATE_STATUS-0}" ;;
esac'
    stub systemd-run
    unset FIXTURE_AFTER UPDATE_STATUS UPDATE_STDERR
    export FIXTURE=$SANDBOX/records.json MARKER=$SANDBOX/updated
    records_json "$(date +%s)" >"$FIXTURE"
  }

  begin "the widget reads the records, shows them as plain text, and launches an agent"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  out=$(app "Launch agent" "")
  check "$out" '.loaded and .problem == "" and .refreshing == false' "the first read did not complete"
  check "$out" '[.agents[].name] == ["Claude Code", "OpenRouter", "DeepSeek", "Fireworks", "Codex", "Hermes", "<b>Evil</b><img src=x>"]' "agents"
  check "$out" '.tooltip == "Claude Code 95%, Codex 50%, <b>Evil</b><img src=x> 100%"' "tooltip"
  check "$out" '.page.buttons == [{text: "Launch agent", enabled: true}, {text: "Refresh", enabled: true}]' "buttons"
  check "$out" '.page.texts | index("Claude Code") and index("Pro") and index("Weekly (7-day)") and index("Balance") and index("$3.50 left") and index("€2.00 left")
                and index("Tokens: 1.2M today, 3.3M this week") and index("Work · Max") and index("<b>Evil</b><img src=x>")' \
    "the page lacks a name, plan, limit, balance, tokens line, account or the raw agent name"
  check "$out" '.page.texts | any(contains("42%") and contains("resets in 2h 10m"))' "a limit shows its percent and reset time"
  check "$out" '.page.texts | index("Updated 2d 3h ago")' "the page does not say that a record is two days old"
  check "$out" '.page.bars == [0.42, 0.95, 0, 0.42, 0.8, 0.175, 0.05, 0.5, 1]' "meters of limits, accounts and balances, in page order"
  check "$out" '.page.notPlain == []' "text that is not plain text"
  qml_log_is_clean || fail "QML reported errors: $(head -c 800 "$QML_LOG")"
  [[ $(calls_of cachyos-agent) == 'usage --json' ]] || fail "the widget should run cachyos-agent usage --json once and nothing else: $(calls_of cachyos-agent)"
  [[ $(calls_of systemd-run) == '--user --scope --quiet -- cachyos-agent launch' ]] \
    || fail "Launch agent did not start cachyos-agent launch in its own scope: $(calls_of systemd-run)"
  ok
  cleanup_sandbox

  begin "Launch agent returns at once, so a second click starts a second agent while the first runs"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  # An agent session lasts as long as its terminal is open: the stub does too.
  stub systemd-run 'sleep 4'
  out=$(app "Launch agent+Launch agent" "")
  [[ $(calls_of systemd-run) == $'--user --scope --quiet -- cachyos-agent launch\n--user --scope --quiet -- cachyos-agent launch' ]] \
    || fail "two clicks should start two agents, though the first is still running: $(calls_of systemd-run)"
  check "$out" '.problem == "" and .page.buttons == [{text: "Launch agent", enabled: true}, {text: "Refresh", enabled: true}]' "the page should stay usable while an agent runs"
  qml_log_is_clean || fail "QML reported errors: $(head -c 800 "$QML_LOG")"
  ok
  cleanup_sandbox

  begin "clicking the panel icon opens the widget and reads the records again"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  out=$(app compact "")
  check "$out" '.compactIcon == "utilities-terminal" and .during.expanded and .expanded' "the compact representation is the terminal icon, and a click expands the widget"
  [[ $(calls_of cachyos-agent) == $'usage --json\nusage --json' ]] || fail "opening the widget should read the records again: $(calls_of cachyos-agent)"
  qml_log_is_clean || fail "QML reported errors: $(head -c 800 "$QML_LOG")"
  ok
  cleanup_sandbox

  begin "Refresh collects new usage with cachyos-agent usage update and then reads it"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  jq '. + [{id: "after", name: "After Update", ready: true, tierLabel: "pro"}]' "$FIXTURE" >"$SANDBOX/after.json"
  export FIXTURE_AFTER=$SANDBOX/after.json
  out=$(app Refresh "After Update")
  check "$out" '.problem == "" and .refreshing == false and (.agents | map(.name) | index("After Update"))' "the records read after the update were not shown"
  check "$out" '.during.refreshing and (.during.buttons | map(select(.text == "Refresh") | .enabled) == [false])' "Refresh should be busy, and off, while the update runs"
  [[ $(calls_of cachyos-agent) == $'usage --json\nusage update\nusage --json' ]] \
    || fail "expected a read, the update, then another read; got: $(calls_of cachyos-agent)"
  qml_log_is_clean || fail "QML reported errors: $(head -c 800 "$QML_LOG")"
  ok
  cleanup_sandbox

  begin "a failed update is reported and the records are still read"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  export UPDATE_STATUS=1 UPDATE_STDERR="claude: no network"
  out=$(app Refresh "Claude Code")
  check "$out" '.problem == "cachyos-agent usage update failed: claude: no network" and (.agents | length) == 7' "the failed update should be reported beside the records"
  check "$out" '.page.texts | index("cachyos-agent usage update failed: claude: no network")' "the problem is not on the page"
  ok
  cleanup_sandbox

  begin "a failed update's message goes away with the next successful read"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  export UPDATE_STATUS=1 UPDATE_STDERR="claude: no network"
  # The read the timer or the popup makes later finds good records: the red
  # message must not stay above them until the next Refresh.
  out=$(app Refresh+reload "Claude Code")
  check "$out" '.settled[0].problem == "cachyos-agent usage update failed: claude: no network"
                and (.settled[0].page.texts | index("cachyos-agent usage update failed: claude: no network"))' "the read right after the failed update should still say why"
  check "$out" '.problem == "" and (.page.texts | index("cachyos-agent usage update failed: claude: no network") | not) and (.agents | length) == 7' \
    "a later successful read should drop the failed update's message"
  [[ $(calls_of cachyos-agent) == $'usage --json\nusage update\nusage --json\nusage --json' ]] || fail "expected a read, the update, a read, then the later read; got: $(calls_of cachyos-agent)"
  ok
  cleanup_sandbox

  begin "a usage command that fails shows why instead of agents"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  stub cachyos-agent 'echo "usage: records are unreadable" >&2; exit 1'
  out=$(app dump "")
  check "$out" '.loaded and .agents == [] and .problem == "cachyos-agent usage --json failed: usage: records are unreadable"' "the failure"
  check "$out" '.page.texts | index("cachyos-agent usage --json failed: usage: records are unreadable") and (index("Loading usage…") | not)' "the failure is not on the page"
  ok
  cleanup_sandbox

  begin "with no records the widget says how to collect them"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  stub_agent
  echo '[]' >"$FIXTURE"
  out=$(app dump "")
  check "$out" '.agents == [] and .problem == "" and (.page.texts | index("No agent usage yet. Press Refresh to collect it, and run `cachyos-agent usage schedule on` to keep it current."))' "the empty state"
  ok
  cleanup_sandbox
else
  unverified "the widget end to end" "qml6, the Plasma executable data engine or the Plasma QML modules are not installed"
fi

if command -v qml6 >/dev/null && [[ -d $QML_DIR/org/kde/kcmutils && -d $QML_DIR/org/kde/plasma/configuration ]]; then
  begin "the settings page edits the refresh interval and the settings dialog offers it"
  make_sandbox
  QML_LOG=$SANDBOX/qml.log
  out=$(qml_json "$HARNESS/config.qml" -- "$PKG/contents/ui/configGeneral.qml" "$PKG/contents/config/config.qml")
  check "$out" '.loaded and .spin == {value: 120, from: 30, to: 3600}' "setting cfg_refreshIntervalSec should move the spin box, which allows 30 to 3600 seconds"
  check "$out" '.categories | map([.name, .source]) == [["General", "configGeneral.qml"]]' "the settings dialog should offer the page"
  qml_log_is_clean || fail "QML reported errors: $(head -c 800 "$QML_LOG")"
  ok
  cleanup_sandbox
else
  unverified "the settings page" "qml6, kcmutils or the Plasma configuration module is not installed"
fi
