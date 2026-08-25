---
name: cachyos
description: >
  REQUIRED for CachyOS-specific system administration: kernels, optimized repos,
  schedulers, hardware profiles, boot and snapshots, packaged desktop defaults,
  handheld systems, and CachyOS packaging. Use for linux-cachyos*, Kernel Manager,
  ISA repos, scx_loader, chwd, Limine, snapper, cachy-chroot, Noctalia/UWSM,
  deckify, or CachyOS-PKGBUILDS. Do not use for ordinary application work or a
  vanilla Arch system unless the task is adding or managing CachyOS repositories.
---

# CachyOS Skill

Manage a running [CachyOS](https://cachyos.org/) install. CachyOS is a performance-first rolling Arch derivative with its own kernels, ISA-optimized repos, settings, hardware profiles, and a separate handheld ISO.

This skill covers end-user and admin work on an installed system. It is not a substitute for the [CachyOS wiki](https://wiki.cachyos.org/). Deep PKGBUILD authoring lives only in [`packaging.md`](packaging.md).

## When This Skill MUST Be Used

**ALWAYS invoke this skill before ANY of these on a CachyOS machine:**

- Installing, removing, or switching `linux-cachyos*` kernels or their `*-nvidia` / `*-zfs` modules
- Editing `/etc/pacman.conf` or any `cachyos*-mirrorlist`
- Loading or configuring `scx_*` schedulers, `scx_loader`, `ananicy-cpp`, `gamemode`, or `game-performance`
- Overriding sysctl, udev, ZRAM, or I/O scheduler behavior
- Running `chwd` or changing GPU / handheld / T2 profiles
- Changing bootloader, snapper, or recovery procedure
- Editing desktop / compositor config that a `cachyos-*-settings` package owns
- Working on a handheld (Steam Deck, ROG Ally, Legion Go, MSI Claw, …)
- Adding Cachy repos to an existing Arch box

**If you are about to treat this machine as vanilla Arch, STOP.**

**Do NOT use this skill as the required path for writing CachyOS PKGBUILDs.** Read [`packaging.md`](packaging.md) for that.

## Topic Guides

Read the matching guide before starting:

- [`kernel.md`](kernel.md) — `linux-cachyos*` variants, Kernel Manager, matching modules
- [`repos.md`](repos.md) — ISA repos, `pacman.conf` order, `cachyos-repo.sh`
- [`performance.md`](performance.md) — scx, ananicy-cpp, gamemode, ZRAM, overrides
- [`hardware.md`](hardware.md) — `chwd` profiles, GPU migration, NVIDIA modules
- [`boot.md`](boot.md) — Limine, snapper, `cachy-chroot` recovery
- [`desktop.md`](desktop.md) — settings packages, `/etc/skel`, Hyprland Noctalia+UWSM
- [`install.md`](install.md) — desktop vs handheld ISO, installer, Arch overlay
- [`packaging.md`](packaging.md) — CachyOS-PKGBUILDS, march/LTO/PGO
- [`handheld.md`](handheld.md) — Handheld Edition, `linux-cachyos-deckify`, `scx_lavd`

## Critical Safety Rules

**NEVER treat CachyOS as vanilla Arch.** Arch Wiki is background. Cachy tools and this skill are the procedure.

**NEVER edit shipped files under `/usr/lib`.** They belong to CachyOS packages and will be overwritten.

```
# READ-ONLY examples — NEVER EDIT
/usr/lib/sysctl.d/70-cachyos-settings.conf
/usr/lib/udev/rules.d/          # shipped I/O and zram rules
/usr/share/scx_loader/config.toml
```

**ALWAYS override here instead:**

- `/etc/sysctl.d/*.conf`
- `/etc/udev/rules.d/`
- `/etc/scx_loader/config.toml` (copy from `/usr/share/scx_loader/config.toml` first)
- `/etc/default/limine`

**NEVER put `[core]` above Cachy ISA repos in `/etc/pacman.conf`.** Cachy `v3` / `v4` / `znver4` entries MUST sit above `[core]`. See [`repos.md`](repos.md).

**Do not disable `ananicy-cpp` merely because `scx_loader` is active.** Current CachyOS guidance says they are usually compatible; disable Ananicy as a troubleshooting step if sched-ext stalls or becomes unstable. `gamemode` still overlaps with Ananicy's process-priority changes. See [`performance.md`](performance.md).

**NEVER put a handheld on a desktop kernel.** Handheld MUST use `linux-cachyos-deckify`. See [`handheld.md`](handheld.md).

**When wiki, README, and old articles disagree, do not pick a side.** Verify live:

```bash
pacman -Si linux-cachyos linux-cachyos-lts linux-cachyos-server
kerver
```

Known unresolved conflicts (sources 2026-08-24, ISO 260809):

| Topic | One source | Other source | What you do |
|-------|------------|--------------|-------------|
| `linux-cachyos-lts` scheduler | wiki: BORE | linux-cachyos README: EEVDF | `pacman -Si linux-cachyos-lts` / `kerver` |
| `linux-cachyos-server` preemption | wiki: none | README: lazy | `pacman -Si linux-cachyos-server` |
| Default scheduler | old articles: BORE | current default: tuned EEVDF | Trust live kernel, not blog posts |
| NVMe I/O scheduler | some wiki examples: `none` | shipped udev: **kyber** | `cat /sys/block/nvme0n1/queue/scheduler` |

## Privilege Escalation

Use `sudo` in a visible terminal for privileged work. NEVER start interactive `sudo` or `pacman` prompts that hang a headless agent unless the user is present. Use `pacman --noconfirm` only after the user approved the package set.

## System Architecture

| Component | Purpose | Safe edit location |
|-----------|---------|--------------------|
| Arch Linux | Base | `/etc/`, `~/.config/` |
| Cachy ISA repos | Rebuilt packages (`v3` / `v4` / `znver4`) | `/etc/pacman.conf`, `/etc/pacman.d/cachyos*-mirrorlist` |
| `linux-cachyos*` | Kernels + prebuilt modules | Kernel Manager; matching `*-nvidia` / `*-zfs` |
| CachyOS-Settings | sysctl, udev, zram | `/etc/sysctl.d/`, `/etc/udev/rules.d/` |
| `scx_loader` | sched-ext | `/etc/scx_loader/config.toml` |
| `chwd` | Hardware profiles | `chwd` CLI, not hand-edited profile packages |
| Limine + snapper | Default boot + snapshots | `/etc/default/limine` |
| `cachyos-*-settings` | DE / WM defaults | user `~/.config/` after first login |

## Decision Framework

1. **Is this a handheld?** Read [`handheld.md`](handheld.md) first. Stop if you were about to use desktop ISO/kernel/scheduler advice.
2. **Is it a kernel or module change?** [`kernel.md`](kernel.md). Install the matching `*-nvidia` / `*-zfs` package. Use Kernel Manager.
3. **Is it pacman / repos / `-bin` packages?** [`repos.md`](repos.md). Check ISA with `/lib/ld-linux-x86-64.so.2 --help`.
4. **Is it scheduling, gamemode, or sysctl/udev?** [`performance.md`](performance.md). Inspect the active services and change only the layer involved; Ananicy does not need to be disabled solely for scx.
5. **Is it GPU or other hardware?** [`hardware.md`](hardware.md). `chwd -r` then `chwd -a`. Do not fight `nvidia-dkms` with Cachy module packages.
6. **Is it boot, snapshots, or an unbootable system?** [`boot.md`](boot.md). `cachy-chroot` + Btrfs preset from a live ISO.
7. **Is it a desktop / compositor tweak?** [`desktop.md`](desktop.md). `/etc/skel` does not update existing users.
8. **Is it install media or converting Arch?** [`install.md`](install.md). Existing Arch is a repo overlay, not a conversion.
9. **Is it a PKGBUILD?** [`packaging.md`](packaging.md) only.

## Out of Scope

- Vanilla Arch advice as if Cachy packages and repos were absent
- Another distro's agent skill text
- Inventing a default-agent CLI, mise stubs, or hotkeys (CachyOS has none)
- ISO engineering (image build, Calamares branding, first-login hooks). [`install.md`](install.md) covers using the published ISO only.
- Deep PKGBUILD authoring except via [`packaging.md`](packaging.md)

## Example Requests

- "Switch me to the LTS kernel" → [`kernel.md`](kernel.md), Kernel Manager, matching modules, then `kerver`
- "Enable scx_lavd on boot" → [`performance.md`](performance.md), inspect the current scheduler stack, then edit `/etc/scx_loader/config.toml`
- "I swapped my NVIDIA card for AMD" → [`hardware.md`](hardware.md), `chwd --list-installed`, `chwd -r <profile>`, reboot, `chwd -a`
- "System will not boot after a kernel update" → [`boot.md`](boot.md), live ISO, `cachy-chroot`, Btrfs preset, Limine snapshot
- "Tune Hyprland gaps" → [`desktop.md`](desktop.md). Do not follow the stock Hyprland wiki as if this were a stock install. Do not install archived `cachyos-hyprland-settings`.
- "Add Cachy repos to this Arch box" → [`repos.md`](repos.md) + [`install.md`](install.md). Overlay, not a conversion.
