# Optimized repositories

Read this before editing `/etc/pacman.conf`, changing ISA repos, or adding Cachy packages to an Arch box.

## Why this is not Arch

Cachy rebuilds Arch packages for `x86-64-v3`, `x86-64-v4`, and `znver4` (Zen 4/5), plus a generic `[cachyos]` repo for Cachy-specific packages (kernels, settings, `chwd`, …). Selected packages also get LTO / PGO / BOLT. See [Optimized Repositories](https://wiki.cachyos.org/features/optimized_repos/).

**`-bin` packages are NOT ISA-optimized.** NEVER treat a `foo-bin` as the Cachy-optimized build.

## Check the CPU first

```bash
/lib/ld-linux-x86-64.so.2 --help | grep supported
# Prefer this path. `ld-linux` may not be on PATH.

# Example of a v4-capable CPU:
#   x86-64-v2 (supported, searched)
#   x86-64-v3 (supported, searched)
#   x86-64-v4 (supported, searched)

# Zen 4/5 only, for znver4 repos:
gcc -march=native -Q --help=target 2>&1 | grep -Po '^\s+-march=\s+\K(\w+)$'
# znver4 or znver5 → znver4 repos are eligible
```

Pick **one** ISA line: `v3`, `v4`, or `znver4`. Do not stack v3 and v4 together.

ISA pick is **CPU table first, then the loader check.** The English [Preparation](https://wiki.cachyos.org/installation/installation_prepare/) table lists Intel 12th–15th gen consumer chips (Alder / Raptor / Lunar / Arrow Lake) under **v3**. The v4 Intel list is Xeon / Ice Lake / Rocket Lake / Skylake-X / etc. The loader check is required but not sufficient: if the table says v3, stay on v3 even if `/lib/ld-linux-x86-64.so.2 --help` prints v4. The English [Optimized Repositories](https://wiki.cachyos.org/features/optimized_repos/) page does **not** say “hybrids can pass a v4 check.”

## pacman.conf order — MUST

Cachy ISA repos MUST sit **above** `[core]`. **NEVER put `[core]` first.**

Keep `[cachyos]`, `[core]`, `[extra]`, and `[multilib]` present. When migrating ISA, replace only the `cachyos-v3` / `v4` / `znver4` blocks.

`[cachyos]` can ship Cachy’s **pacman fork**. Enabling ISA repos is not “replace pacman with vanilla Arch pacman.”

Do not guess enabled repos from a pasted `pacman.conf` snippet. Prefer:

```bash
pacman-conf --repo-list
pacman -Qi pacman
pacman -Si pacman
```

v4 example (v3 is the same pattern with `cachyos-v3-mirrorlist`):

```
[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
```

znver4 (AMD Zen 4/5 only). Repo **names** change; the **mirrorlist file does not**. There is no `cachyos-znver4-mirrorlist`. Include stays `/etc/pacman.d/cachyos-v4-mirrorlist`:

```
[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-core-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-extra-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
```

An ISA swap is a **whole-system reinstall**, not a repo toggle. After editing `pacman.conf`:

```bash
sudo pacman -Scc    # confirm twice
sudo pacman -Sy     # documented exception for this ISA migration only
pacman -Qqn | sudo pacman -S -
# then reboot
```

**NEVER generalize that `pacman -Sy`.** Everyday updates stay `pacman -Syu`. Partial upgrades are still forbidden.

## Add Cachy repos to an existing Arch install

This is a **repo overlay**, not a conversion to CachyOS. The machine does not become a Cachy ISO install. See [`install.md`](install.md).

```bash
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz
cd cachyos-repo
sudo ./cachyos-repo.sh
```

Remove later with the same tarball and `sudo ./cachyos-repo.sh --remove`.

ALWAYS prefer `cachyos-repo.sh` over hand-editing unless you are fixing a broken order the script already wrote.

## MUST / NEVER

- MUST check ISA with `/lib/ld-linux-x86-64.so.2 --help` before changing repos.
- MUST pick ISA from the [prepare-page CPU table](https://wiki.cachyos.org/installation/installation_prepare/) plus `/lib/ld-linux-x86-64.so.2 --help`. Consumer 12th-gen+ Intel hybrids are **v3** on that table. NEVER promote them to v4 because the loader printed v4.
- MUST keep Cachy ISA sections above `[core]`.
- MUST treat an ISA swap as a whole-system reinstall (`pacman -Qqn | sudo pacman -S -`), not a toggle.
- MUST treat `-bin` packages as generic binaries, not Cachy-optimized builds.
- NEVER drop `[cachyos]` when swapping v3/v4/znver4, and NEVER replace Cachy’s pacman with vanilla Arch pacman as part of enabling ISA repos.
- NEVER invent a `cachyos-znver4-mirrorlist`. znver4 sections Include `cachyos-v4-mirrorlist`.
- NEVER generalize the ISA-migration `pacman -Sy`. Normal rule is `pacman -Syu` / no partial upgrades.
- NEVER edit files under `/usr/lib` to "enable" repos.
