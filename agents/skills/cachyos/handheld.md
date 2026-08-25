# Handheld Edition

Read this before touching a Steam Deck, ROG Ally, Legion Go, MSI Claw, or any other Cachy handheld. Getting this wrong is easy and expensive: unbootable Deck, broken Game Mode, dead battery scheduler.

This file is **stricter** than the desktop topics. If a desktop skill and this file disagree, this file wins on handheld hardware.

## Separate product

Handheld Edition is a **dedicated ISO**, not a package group you add to the desktop ISO. See [Handheld Edition](https://wiki.cachyos.org/installation/installation_handheld/).

| MUST | NEVER |
|------|--------|
| Install from the **Handheld ISO** | Install from the desktop ISO and "add gamescope later" as the supported path |
| Boot `linux-cachyos-deckify` | Any other `linux-cachyos*` flavor |
| Leave **LAVD** (`scx_lavd`) as the default scx scheduler | Replace LAVD with a random desktop scx on a hunch |
| Keep the **gamescope session** / Game Mode as the session the ISO installed | Treat this as a normal KDE/Hyprland laptop |

Desktop ISO + `chwd -i handheld` is not the Handheld Edition. `chwd` handheld profiles exist for hardware quirks; they do not replace the handheld image, deckify kernel, or gamescope session.

Official support (download page, 2026-08-24): ROG Ally, Steam Deck OLED and LCD, Legion Go, Legion Go S. Handheld Edition DE is **KDE Plasma only**. Handheld ISO version may lag Desktop `260809` — confirm the file on https://cachyos.org/download/.

```bash
chwd --list
chwd --list-installed
sudo chwd -a
sudo chwd -i handheld.steam-deck
sudo chwd -i handheld.rog-ally
sudo chwd -i handheld.intel-msi-claw
```

## Kernel

```bash
uname -r
pacman -Q linux-cachyos-deckify
```

**MUST** stay on `linux-cachyos-deckify` (plus matching `linux-cachyos-deckify-headers` and, if NVIDIA-class handheld GPU requires it, the matching module package). Wiki: handheld-specific patches on the base patchset; other kernels are **unsupported** on handhelds.

**NEVER** "upgrade" a Deck/Ally to default `linux-cachyos` because Kernel Manager listed it first.

## Scheduler

Handheld Edition default is **`scx_lavd`** via `scx_loader` (not the old `scx.service`). That pairing is the battery/FPS tune the edition ships.

```bash
systemctl status scx_loader.service
# config: /etc/scx_loader/config.toml
```

You MAY pass LAVD `--performance` / `--powersave` / `--autopower` through the loader config. Do not replace the shipped LAVD setup with `ananicy-cpp` on a hunch. If Ananicy is also installed, current guidance does not require disabling it unless scx stalls or becomes unstable. See [`performance.md`](performance.md).

Stale Handheld README text that mentions `scx.service`, systemd-boot-as-default, or bcachefs is **wrong** as of current wiki/changelogs: default bootloader is Limine + snapshots; bcachefs was dropped as a promised default. Verify live.

## Session

First boot can sit on Steam download for up to ~2 minutes. That is expected.

**NEVER** replace the gamescope / Game Mode session with a stock desktop session "so the agent can see a normal DE" unless the user explicitly asked to abandon Handheld Edition behavior.

If the session is broken, recover with the **Handheld ISO** + [`boot.md`](boot.md) (`cachy-chroot`, Btrfs preset). Prefer Limine snapshots.

## Install notes (only if you are installing)

- Prefer **Erase Disk** on a device that previously had another layout. Replace-partition is unreliable here.
- Dual boot: manual partition, ESP `/boot` FAT32 **≥ 4096 MiB**, root Btrfs.
- Limine is default; systemd-boot is offered and still has **no** Cachy snapshot menu.

## MUST / NEVER (repeat)

- MUST use Handheld ISO + `linux-cachyos-deckify` + `scx_lavd` + the shipped gamescope session.
- MUST verify stale handheld READMEs against the wiki and the running system.
- NEVER boot a handheld on `linux-cachyos`, `-rt-bore`, `-server`, or `-hardened`.
- NEVER follow desktop Hyprland / KDE wiki steps as if this were a tower.
- NEVER replace the shipped LAVD setup with Ananicy as a speculative gaming tweak.
