#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Adapted from Omarchy bin/omarchy-agent-account-* (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
# Helpers shared by the cachyos-agent account commands. Source it after
# lib/common.sh, from a script that is a real file under bin/:
#   source "$CACHYOS_AGENT_ROOT/lib/accounts.sh"
# The registry itself lives in cachyos-agent-account-state; this file holds what
# the shell commands around it need to agree on.
# shellcheck disable=SC2034 # the ACCT_* variables are set for the scripts that source this

ACCT_PROVIDERS=(claude codex grok)

# jq text for any command that prints an account's label, email or plan, which
# come from the CLI's own files and a vendor's response and can hold an escape
# sequence: put it before the program, as in jq -r "$ACCT_JQ_CLEAN"' .label | clean'.
# It drops every control character, C1 included (U+009B is an escape on some
# terminals), as the usage report does; a tab would also shift columns.
ACCT_JQ_CLEAN='def clean: if type == "string" then gsub("[\u0000-\u001f\u007f-\u009f]"; "") else . end;'

# acct_is_provider <word>: whether the word names a provider with accounts.
# Compared whole: a word that holds several names, such as "codex grok", is
# not one of them.
acct_is_provider() {
  local provider
  for provider in "${ACCT_PROVIDERS[@]}"; do
    [[ ${1-} == "$provider" ]] && return 0
  done
  return 1
}

# acct_provider <provider>: set what the commands need to know about it, or
# fail for a word that is not a provider.
#   ACCT_NAME      how messages call it
#   ACCT_HOME_ENV  the variable that points the CLI at a config home
#   ACCT_SITE      where its sign-in page lives
#   ACCT_LOGIN     the CLI's own sign-in command
# cachyos-agent-account-state keeps the same names and variables for the
# registry side.
acct_provider() {
  case ${1-} in
    claude)
      ACCT_NAME=Claude ACCT_HOME_ENV=CLAUDE_CONFIG_DIR ACCT_SITE=claude.ai
      ACCT_LOGIN=(claude auth login)
      ;;
    codex)
      ACCT_NAME=Codex ACCT_HOME_ENV=CODEX_HOME ACCT_SITE=chatgpt.com
      ACCT_LOGIN=(codex login)
      ;;
    grok)
      ACCT_NAME=Grok ACCT_HOME_ENV=GROK_HOME ACCT_SITE=x.ai
      ACCT_LOGIN=(grok login)
      ;;
    *) return 1 ;;
  esac
}

# acct_default_agent: the default agent, or nothing when none is chosen or the
# launcher's cachyos-agent-default is not installed.
acct_default_agent() {
  if ca_cmd_present cachyos-agent-default; then
    cachyos-agent-default 2>/dev/null || true
  fi
}

# acct_args "$@": set ACCT_ARGS to the arguments with the provider in front.
# The provider can be left out when the default agent is one of them:
# `cachyos-agent account use work`. Use it as
#   acct_args "$@"; set -- "${ACCT_ARGS[@]}"
acct_args() {
  local default
  ACCT_ARGS=("$@")
  if acct_is_provider "${1-}"; then
    return 0
  fi
  default=$(acct_default_agent)
  if acct_is_provider "$default"; then
    ACCT_ARGS=("$default" "$@")
  fi
}

# acct_usage_refresh <usage-update option> <provider>: collect that provider's
# usage record again in the background, so the panel and `cachyos-agent usage`
# show a change made here. The usage commands are a separate feature and may not
# be installed.
acct_usage_refresh() {
  if ca_cmd_present cachyos-agent-usage-update; then
    cachyos-agent-usage-update "$1" "$2" >/dev/null 2>&1 &
  fi
}
