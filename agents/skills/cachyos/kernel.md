# Kernel management

Read this before installing, removing, or switching any `linux-cachyos*` kernel or its out-of-tree modules.

## Tools

Prefer **CachyOS Kernel Manager** (`cachyos-kernel-manager`) to install or switch on a desktop — it keeps headers and matching module packages aligned. Headless/server: `pacman -S` the kernel, headers, and matching `*-nvidia*` / `*-zfs` packages is fine.

```bash
# What is running
kerver
uname -r

# What is installed
pacman -Q | grep -E '^linux-cachyos'

# What the package metadata currently claims (ALWAYS do this when sources conflict)
pacman -Si linux-cachyos linux-cachyos-lts linux-cachyos-server linux-cachyos-deckify
```

## Variants

All Cachy kernels ship the CachyOS base patchset. Most also have a `-lto` sibling built with Clang. Default `linux-cachyos` is already Clang ThinLTO.

| Package | Role | Notes you MUST honor |
|---------|------|----------------------|
| `linux-cachyos` | Default. Use this unless you have a reason not to. | Tuned **EEVDF**, 1000 Hz, Clang ThinLTO + AutoFDO. Old articles that say the default is BORE are wrong. |
| `linux-cachyos-eevdf` | Stock EEVDF with Cachy responsiveness tweaks | Different package from the default. Do not confuse them. |
| `linux-cachyos-bore` | BORE scheduler | Explicit BORE variant. |
| `linux-cachyos-bmq` | BMQ (Project C) | **Does not support sched-ext.** Do not load `scx_*` on it. |
| `linux-cachyos-hardened` | linux-hardened + aggressive config | BORE. **Does not support sched-ext.** Expect a worse desktop. |
| `linux-cachyos-lts` | Latest LTS, minimally patched | **CONFLICT:** wiki (2026-08-24) says BORE; linux-cachyos README says EEVDF. Verify with `pacman -Si` / `kerver`. Do not guess. |
| `linux-cachyos-rc` | Linus mainline + newest Cachy patchset | For testing new patchset features. |
| `linux-cachyos-server` | Server tune: 300 Hz, stock EEVDF | **CONFLICT:** wiki says no preemption; README says lazy preemption. Verify live. Not a desktop kernel. |
| `linux-cachyos-rt-bore` | PREEMPT_RT + BORE | **RT ≠ gaming.** Realtime preemption makes more code preemptible and **hurts** game throughput. Never install this to "improve FPS". |
| `linux-cachyos-deckify` | Handheld default | Handheld-specific patches (Steam Deck, Ally, Claw, …). Wiki lists BORE. **MUST** be the kernel on Handheld Edition. Unsupported to run any other kernel on a handheld. See [`handheld.md`](handheld.md). |

AutoFDO + Propeller is expensive (build twice). It is only on default `linux-cachyos` for that reason.

## Matching modules — NEVER use random -dkms as the first choice

Cachy ships prebuilt modules for each kernel flavor. A kernel bump does **not** require you to rebuild NVIDIA or ZFS if you install the matching package.

```
linux-cachyos                  # image
linux-cachyos-headers
linux-cachyos-nvidia           # proprietary NVIDIA module, patched
linux-cachyos-nvidia-open      # open NVIDIA module
linux-cachyos-zfs
linux-cachyos-dbg              # unstripped, needed to profile AutoFDO
```

The same suffixes exist on the other flavors (`linux-cachyos-lts-nvidia`, `linux-cachyos-hardened-lto-zfs`, …).

**ALWAYS install the module package that matches the exact kernel package you boot.**

**NEVER "fix" NVIDIA by adding `nvidia-dkms` on top of a Cachy prebuilt module.** That fights `chwd` and the kernel packages. See [`hardware.md`](hardware.md).

DKMS is the fallback when no prebuilt module exists for that pair, not the default.

## Switch procedure

**MUST install and boot the replacement kernel before removing the known-good fallback.** Do not `pacman -R` the old image until the new one is the running kernel.

1. Snapshot if the filesystem is Btrfs (`boot.md`).
2. Open Kernel Manager, or `sudo pacman -S linux-cachyos-<variant> linux-cachyos-<variant>-headers` plus the matching `*-nvidia*` / `*-zfs` if those filesystems/GPUs are in use. Leave the current kernel installed.
3. Confirm Limine/systemd-boot/GRUB picked up the new image (`limine-mkinitcpio` or the installed hook — Cachy pacman hooks usually rebuild initramfs).
4. Reboot into the new kernel.
5. `kerver` and `uname -r` MUST match the package you intended. Only then may you remove the previous kernel and its matching modules.
6. If scx was enabled, confirm the new kernel still supports sched-ext (not BMQ/hardened).

## MUST / NEVER

- MUST keep headers and modules on the same flavor as the running image.
- MUST install and boot the replacement kernel before removing the known-good fallback. Verify `uname -r` / `kerver` after reboot.
- MUST use `linux-cachyos-deckify` on handheld hardware.
- MUST verify LTS scheduler and server preemption live; do not resolve the wiki/README conflict yourself.
- NEVER install `linux-cachyos-rt-bore` for gaming.
- NEVER load `scx_*` on BMQ or hardened.
- NEVER edit kernel package files under `/usr/lib/modules/`.
