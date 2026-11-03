#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# The Plasma widget in plasmoid/org.cachyos.agent: its package files, the QML
# it is written in, and the JavaScript that shapes usage records for it. There is
# no desktop here, so the JavaScript runs under qml6 with the offscreen platform,
# through test/plasmoid/records.qml. A check whose tool or Qt module is missing is
# reported UNVERIFIED and does not fail the case.
# The jq programs are single-quoted so that their $ reaches jq as written.
# shellcheck disable=SC2016
# shellcheck source=../lib.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib.sh"

PKG=$REPO_ROOT/plasmoid/org.cachyos.agent
HARNESS=$REPO_ROOT/test/plasmoid
QML_DIR=/usr/lib/qt6/qml
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

# records_json <now in epoch seconds>: the usage records every check below reads,
# with the times that matter given relative to <now>.
records_json() {
  local now=$1 iso='+%Y-%m-%dT%H:%M:%S'
  sed -e "s/@SESSION@/$(date -u -d "@$((now + 7830))" "$iso").123456+00:00/" \
    -e "s/@WEEK@/$(date -u -d "@$((now + 3 * 86400 + 4 * 3600 + 30))" "$iso")Z/" \
    -e "s/@ELAPSED@/$(date -u -d "@$((now - 60))" "$iso")Z/" \
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
    "id": "fireworks", "name": "Fireworks", "ready": true, "tierLabel": "Prepaid",
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
  check "$out" '.agents[3].balance == {remainingText: "€2.00 left", detailText: "", fraction: -1, low: false}' "a balance with no funding figure has nothing to measure against"
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
