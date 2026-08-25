# Hardware profiles (chwd)

Read this before installing GPU drivers, changing GPU vendors, or applying handheld/T2 profiles.

[chwd](https://wiki.cachyos.org/features/chwd/chwd/) (CachyOS Hardware Detection) installs the package set for the machine: NVIDIA, AMD, Intel, T2 Macs, Steam Deck / Ally / Claw, VMs.

The installer already ran it. Post-install, ALWAYS use `chwd`. NEVER start with raw `pacman -S nvidia-dkms`.

## Discover

```bash
chwd --list          # profiles that match this machine
chwd --list-all      # every profile
chwd --help
sudo chwd --list-installed   # wiki GPU-migration step; confirm output live (help text also mentions kernels)
```

Profiles you will actually see include `nvidia-open-dkms`, `nvidia-dkms-580xx`, `nvidia-dkms-470xx`, `nouveau`, `amd`, `intel`, `macbook-t2`, `virtualmachine`, `handheld`, `handheld.steam-deck`, `handheld.rog-ally`, `handheld.intel-msi-claw`, `broadcom-wl`, `fallback`.

```bash
sudo chwd -a                 # autoconfigure this machine
sudo chwd -i amd             # install one profile
sudo chwd -r nvidia-open-dkms
sudo chwd -f -i <profile>    # force reinstall
```

`--ai_sdk` toggles CachyOS AI SDK profiles for supported GPUs. Only use it when the user asked for that stack.

## GPU migration (NVIDIA ↔ AMD)

Follow [Switching Between NVIDIA and AMD GPUs](https://wiki.cachyos.org/features/chwd/gpu_migration/). Order matters.

**NVIDIA → AMD**

1. `sudo pacman -Syu`
2. `sudo chwd --list-installed`
3. `sudo chwd -r <nvidia-profile>`
4. Shutdown, fit the AMD card, boot
5. `sudo chwd -a`
6. Initramfs is usually rebuilt by a pacman hook. If the bootloader needs a nudge: Limine `sudo limine-mkinitcpio`; systemd-boot `sudo sdboot-manage gen`; GRUB `sudo grub-mkconfig -o /boot/grub/grub.cfg`
7. Reboot. Verify: `glxinfo | grep "OpenGL renderer"` or `vulkaninfo | grep deviceName`

**AMD → NVIDIA**

1. `sudo chwd -r amd`
2. Shutdown, fit the NVIDIA card, boot
3. `sudo chwd -a`
4. Same bootloader nudge as above
5. Reboot. Verify: `nvidia-smi` or `glxinfo`

NEVER skip `-r` before `-a`. Leftover profiles are how you get black screens.

## NVIDIA modules — do not fight DKMS

On Cachy, the **first** NVIDIA answer is the prebuilt module that matches the running kernel (`linux-cachyos-nvidia` or `linux-cachyos-nvidia-open`, plus the flavor suffix). See [`kernel.md`](kernel.md).

`chwd` NVIDIA profiles may pull `nvidia-*-dkms` for cards that need a specific branch (470xx, 580xx, open). That is `chwd`'s job. **You** MUST NOT add `nvidia-dkms` by hand on top of a working Cachy prebuilt module "because Arch Wiki says so".

If `chwd` and a `linux-cachyos-*-nvidia` package disagree, stop and show the user `chwd --list`, `pacman -Q | grep -E 'nvidia|linux-cachyos'`, and `uname -r`. Do not resolve it by installing both.

## MUST / NEVER

- MUST use `chwd -r <old>` then `chwd -a` when the GPU vendor changes.
- MUST keep NVIDIA kernel modules matched to the booted `linux-cachyos*` flavor.
- NEVER install random Arch NVIDIA package sets that ignore `chwd`.
- NEVER edit shipped udev/modprobe under `/usr/lib` to force a driver; override in `/etc`.
- NEVER apply a `handheld.*` profile to a desktop or the reverse without reading [`handheld.md`](handheld.md).
