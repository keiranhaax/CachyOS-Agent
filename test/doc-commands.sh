#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Reading the commands a document shows and judging them against the dispatcher's
# catalog. Sourced by test/cases/85-docs.sh; it never runs on its own.

# doc_commands <file>: the cachyos-agent commands a document shows, one per
# line, as the words that follow the program name (four at most, lowercase
# words only, so an option or a <placeholder> ends them). A command is what
# starts a line in a code block, a line of text, a quoted string or an inline
# code span; a package name in a pacman line, the bare program name in a
# sentence and a hyphenated file name (cachyos-agent-launch) are not.
doc_commands() {
  awk '
    function emit(text,    words, n, i, out) {
      sub(/^[ \t]+/, "", text)
      if (text !~ /^cachyos-agent /) return
      n = split(substr(text, 15), words, /[ \t]+/)
      out = ""
      for (i = 1; i <= n && i <= 4; i++) {
        if (words[i] == "") continue
        if (words[i] !~ /^[a-z][a-z-]*$/) break
        out = out (out == "" ? "" : " ") words[i]
      }
      if (out != "") print out
    }
    /^[ \t]*```/ { fenced = !fenced; next }
    fenced { line = $0; sub(/^[ \t]+/, "", line); sub(/^[$] /, "", line); emit(line); next }
    {
      line = $0
      sub(/^[ \t>*-]*([0-9]+[.])?[ \t]*/, "", line)
      emit(line)
      rest = $0
      while (match(rest, /["\047][ \t]*cachyos-agent /) > 0) {
        quoted = substr(rest, RSTART + 1)
        sub(/["\047].*$/, "", quoted)
        emit(quoted)
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = $0
      while ((start = index(rest, "`")) > 0) {
        rest = substr(rest, start + 1)
        stop = index(rest, "`")
        if (stop == 0) break
        emit(substr(rest, 1, stop - 1))
        rest = substr(rest, stop + 1)
      }
    }' "$1"
}

# choices <args>: the words the first argument of a command with these args
# metadata must be one of, one per line, or nothing when it is free. Args that
# open with a choice (<list|use|stop>, [on|off|status], [show | set [combo] |
# unset]) fix it, unless the choice is optional and a positional follows (account
# use [claude|codex|grok] [account|next]), where the first word may be the second
# argument.
choices() {
  local re='^([<[])([a-z][a-z-]*( \[[a-z]+\])?( ?\| ?[a-z][a-z-]*( \[[a-z]+\])?)+)[]>]'
  local args=$1 opening group rest
  [[ $args =~ $re ]] || return 0
  opening=${BASH_REMATCH[1]} group=${BASH_REMATCH[2]} rest=${args:${#BASH_REMATCH[0]}}
  if [[ $opening == "[" && -n $(flagless "$rest") ]]; then return 0; fi
  sed -E 's/ \[[a-z]+\]//g' <<<"$group" | tr '|' '\n' | tr -d ' '
}

# flagless <args>: the args metadata without its [--flag ...] groups.
flagless() { sed -E 's/\[--[^]]*\]//g; s/[[:space:]]//g' <<<"$1"; }

# first_word_ok <route> <args> <word> <catalog>: whether a documented command may
# follow <route> with the plain word <word>: one of the command's own choices, or
# anything when it takes positional arguments, but not a word that a command with
# subcommands or with only flags would never accept.
first_word_ok() {
  local -a allowed
  mapfile -t allowed < <(choices "$2")
  if ((${#allowed[@]} > 0)); then
    [[ " ${allowed[*]} " == *" $3 "* ]]
  elif [[ $'\n'$4 == *$'\n'"$1 "* ]]; then
    return 1
  else
    [[ -n $(flagless "$2") ]]
  fi
}

# unknown_commands <file> <catalog> <groups>: the documented commands the dispatcher
# does not have, one per line. The catalog is one route and its args metadata per
# line, separated by a tab. A command is known when it is exactly a group, which
# the dispatcher answers with the group's help, or when it starts with a route,
# the longest one (usage update claude is usage update, not usage), and the word
# after the route is one that route takes (local use, not local pause).
unknown_commands() {
  local words route args best best_args rest group
  local -a known_groups=()
  while IFS= read -r group; do known_groups+=("$group"); done <<<"$3"
  while IFS= read -r words; do
    for group in "${known_groups[@]}"; do
      [[ $words == "$group" ]] && continue 2
    done
    best='' best_args=''
    while IFS=$'\t' read -r route args; do
      if [[ $words == "$route" || $words == "$route "* ]] && ((${#route} > ${#best})); then
        best=$route best_args=$args
      fi
    done <<<"$2"
    if [[ -n $best ]]; then
      rest=${words#"$best"}
      rest=${rest# }
      if [[ -z $rest ]] || first_word_ok "$best" "$best_args" "${rest%% *}" "$2"; then continue; fi
    fi
    echo "cachyos-agent $words"
  done < <(doc_commands "$1") | LC_ALL=C sort -u
}

