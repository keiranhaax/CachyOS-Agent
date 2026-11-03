#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Adapted from Omarchy bin/omarchy-theme-color (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
# The color template engine behind the theme commands. Source it after
# lib/common.sh. Omarchy bakes {{ key }} and {{ mix a b 15% }} into its configs
# at theme-set time; here the same two forms are rendered from a palette file.

# theme_kdeglobals: the file Plasma keeps the active color scheme in.
theme_kdeglobals() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}/kdeglobals"
}

# theme_kdeglobals_state: one line that differs after every write to that file,
# by whatever means (inode, size and nanosecond modification time); "missing"
# when there is no file. For asking whether it changed while something ran.
theme_kdeglobals_state() {
  stat -c '%i %s %.9Y' -- "$(theme_kdeglobals)" 2>/dev/null || echo missing
}

# theme_render <palette-file>: expand the placeholders in stdin to stdout.
#   {{ key }}           the palette value of key
#   {{ mix a b 15% }}   a moved 15% of the way towards b, where a and b are
#                       palette keys or literal #rrggbb colors
# The palette file holds `key<TAB>value` lines. An amount is a percentage
# (30%) or a fraction (0.30); a bare number above 1 counts as a percentage, as
# in omarchy-theme-color. A placeholder that cannot be expanded fails the whole
# render instead of leaving raw {{ }} text behind, so capture the output and
# publish it only when this returns 0. Plain POSIX awk: one process expands a
# whole template, mix included.
theme_render() {
  local palette=${1:?theme_render: palette file required}
  [[ -r $palette ]] || ca_die "cannot read palette $palette"
  awk -v palette="$palette" '
    function fail(message) {
      print "theme: " message > "/dev/stderr"
      exit 1
    }

    function is_hex(text) {
      return length(text) == 7 && text ~ /^#[0-9a-fA-F]+$/
    }

    function hex_value(char) {
      return index("0123456789abcdef", tolower(char)) - 1
    }

    function hex_pair(hex, at) {
      return hex_value(substr(hex, at, 1)) * 16 + hex_value(substr(hex, at + 1, 1))
    }

    # A palette key holding a color, or a literal #rrggbb.
    function color(name) {
      if (is_hex(name)) return tolower(name)
      if (!(name in palette_value)) fail("unknown palette key \"" name "\"")
      if (!is_hex(palette_value[name])) fail("\"" name "\" is not a color: " palette_value[name])
      return tolower(palette_value[name])
    }

    function mix(start_name, end_name, amount,    start, finish) {
      start = color(start_name)
      finish = color(end_name)
      if (amount !~ /^([0-9]+[.]?[0-9]*|[.][0-9]+)%?$/) fail("bad mix amount \"" amount "\"")
      if (amount ~ /%$/) {
        sub(/%$/, "", amount)
        amount = amount / 100
      } else {
        amount += 0
        if (amount > 1) amount = amount / 100
      }
      if (amount > 1) amount = 1
      return sprintf("#%02x%02x%02x",
        int(hex_pair(start, 2) * (1 - amount) + hex_pair(finish, 2) * amount + 0.5),
        int(hex_pair(start, 4) * (1 - amount) + hex_pair(finish, 4) * amount + 0.5),
        int(hex_pair(start, 6) * (1 - amount) + hex_pair(finish, 6) * amount + 0.5))
    }

    function expand(expression,    words, count) {
      count = split(expression, words, " ")
      if (count == 1) {
        if (!(words[1] in palette_value)) fail("unknown palette key \"" words[1] "\"")
        return palette_value[words[1]]
      }
      if (count == 4 && words[1] == "mix") return mix(words[2], words[3], words[4])
      fail("cannot read {{ " expression " }} on line " NR)
    }

    BEGIN {
      while ((getline line < palette) > 0) {
        split(line, field, "\t")
        if (field[1] != "") palette_value[field[1]] = field[2]
      }
      close(palette)
    }

    {
      out = ""
      rest = $0
      while ((open = index(rest, "{{")) > 0) {
        out = out substr(rest, 1, open - 1)
        rest = substr(rest, open + 2)
        close_at = index(rest, "}}")
        if (close_at == 0) fail("unterminated {{ on line " NR)
        out = out expand(substr(rest, 1, close_at - 1))
        rest = substr(rest, close_at + 2)
      }
      print out rest
    }
  '
}
