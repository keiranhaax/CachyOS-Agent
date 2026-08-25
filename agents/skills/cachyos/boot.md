# Boot, snapshots, recovery

Read this before changing the bootloader, snapper, or rescuing an unbootable CachyOS install.

## Default: Limine + snapper

On current ISOs (including 260809) **Limine is the default** bootloader and, on Btrfs, **snapper + `limine-snapper-sync`** is enabled. systemd-boot, GRUB, and rEFInd are still offered. See [Offered Boot Managers](https://wiki.cachyos.org/installation/boot_managers/).

| Bootloader | Cachy snapshot integration |
|------------|----------------------------|
| Limine | Yes — `limine-snapper-sync`. Default. |
| GRUB | Yes — `grub-btrfs-support` when that stack is installed. |
| systemd-boot | **No Cachy-provided snapshot integration.** Custom-only. |
| rEFInd | No Cachy snapshot integration. |

If the user chose systemd-boot, NEVER tell them to pick a snapshot from the boot menu. Point them at snapper CLI / `cachy-chroot`, or at migrating to Limine.

Config you MAY edit:

```
/etc/default/limine
```

**NEVER edit shipped Limine files under `/usr/lib` or `/usr/share`.** After config changes, regenerate entries with the installed hook (`limine-mkinitcpio` / `limine-entry-tool` — both ship on Cachy Limine installs).

```bash
sudo limine-mkinitcpio
```

## Snapper

Default Btrfs layout is snapper-managed. Timeline and number cleanup are already set in the shipped snapper config.

```bash
sudo snapper list
sudo snapper create --description "before kernel switch"
```

Restore from the Limine menu: boot the snapshot (read-only), confirm the restore prompt, then reboot. That is the preferred rollback after a bad agent change.

**Prefer `limine-snapper-restore`** (CLI or the Limine-snapper-restore GUI) over Btrfs-Assistant. Assistant restore of `@` does **not** restore matching kernels on the FAT32 `/boot` partition. That mismatch is a common unbootable state. `limine-snapper-restore` restores the snapshot **and** the kernels.

```bash
sudo snapper get-config
limine-snapper-list
# after booting a snapshot, or from a still-running system:
limine-snapper-restore
```

`/etc/limine-snapper-sync.conf` (`MAX_SNAPSHOT_ENTRIES`, name format) limits menu clutter. `/etc/default/limine` can override those settings. After edits: `sudo limine-mkinitcpio`. Dual-boot Windows: `sudo limine-scan`.

Kernel cmdline source of truth is `/etc/default/limine`, not hand-edited kernel stanzas in `/boot/limine.conf` (`limine-mkinitcpio-hook` + `limine-entry-tool` overwrite them).

## Recovery — live ISO + cachy-chroot

Use this when the installed system will not boot. [cachy-chroot](https://wiki.cachyos.org/features/cachy_chroot/) understands Cachy Btrfs subvolumes and LUKS.

1. Boot a CachyOS live ISO (desktop ISO is fine for recovering a desktop; use Handheld ISO only if you need handheld-specific tools).
2. `sudo su`
3. `pacman -Sy cachy-chroot` if the live image is older than the installed tool.
4. `cachy-chroot`
5. Select the **root** partition.
6. If it is Cachy Btrfs, answer **y** to the **CachyOS BTRFS preset**. That mounts the root subvolume plus `/home`, `/var`, `/tmp`, `/srv`. Answer **n** only for a custom or non-Cachy layout.
   Then mount additional partitions: **`/boot`** for Limine / systemd-boot / rEFInd; **`/boot/efi`** for GRUB. Without `/boot` you cannot reinstall kernels or the bootloader.
7. Work inside the chroot (`pacman -Syu`, `mkinitcpio -P`, Kernel Manager packages, Limine regen).
8. `exit` or Ctrl+D. cachy-chroot unmounts and closes LUKS.

```bash
# inside the chroot, typical repair
pacman -Syu
mkinitcpio -P
limine-mkinitcpio    # Limine
# sdboot-manage gen  # systemd-boot
# grub-mkconfig -o /boot/grub/grub.cfg
```

Bootloader gone (BIOS update wiped entries) — still inside `cachy-chroot` with `/boot` mounted:

| Bootloader | UEFI | BIOS |
| --- | --- | --- |
| Limine | `limine-install` | `limine bios-install /dev/sdX` (disk, not partition) |
| systemd-boot | `bootctl install` then `sdboot-manage gen` | n/a |
| GRUB | `grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=cachyos` then `grub-mkconfig -o /boot/grub/grub.cfg` | `grub-install --target=i386-pc /dev/sdX` |
| rEFInd | `refind-install` | n/a |

Then `pacman -Syu linux-cachyos linux-cachyos-headers` (or `linux-cachyos-deckify` on handheld), `limine-mkinitcpio` / `limine-update` if present, `exit`, reboot.

If Btrfs-Assistant already renamed `@` to `@.broken`: move `.snapshots` back onto the restored `@`, chroot, mount `/boot`, then `limine-mkinitcpio` so kernels match. Prefer `limine-snapper-restore` when it is available.

If automount misses `/boot` or a UUID changed, mount that partition by hand from the menu, then fix `/etc/fstab`.

## MUST / NEVER

- MUST prefer Limine snapshots for rollback on default Btrfs installs.
- MUST use `cachy-chroot` + the Cachy Btrfs preset from a live ISO; do not hand-roll `mount -o subvol=...` unless the preset is wrong.
- MUST tell systemd-boot users that Cachy did not wire snapshots into their boot menu.
- NEVER edit shipped files under `/usr/lib` to change Limine defaults; use `/etc/default/limine`.
- NEVER restore by deleting `.snapshots` or `btrfs subvolume delete` on the live root without a plan.
