# Performance tuning

Read this before loading a sched-ext scheduler, enabling gamemode/ananicy, or overriding sysctl/udev/ZRAM.

## Stack — verify the interactions

These layers can overlap, but some combinations affect the same controls. Inspect what is active before changing anything:

| Layer | What it is | When |
|-------|------------|------|
| In-kernel scheduler | EEVDF (default `linux-cachyos`), or BORE/BMQ on those flavors | Always present. Default is enough for many desktops. |
| `scx_loader` + `scx_*` | BPF schedulers from `scx-scheds` / `scx-scheds-git` + `scx-tools` | Desktop/gaming when you want LAVD, bpfland, rusty, … |
| `ananicy-cpp` | Userspace nice/ioclass daemon | Usually compatible with sched-ext; disable it when troubleshooting scx stalls. It overlaps with `gamemode` process-priority changes. |
| `gamemode` | Temporary game profile | Avoid combining it with `ananicy-cpp` unless the user deliberately accepts the overlap. |
| `game-performance` | Cachy wrapper; on this distro it flips `scx_loader` to its Gaming profile while a game runs | Preferred Cachy integration when `scx_loader` is active. |

Cachy's `power-profiles-daemon` is patched: switching Power Saver / Balanced / Performance in KDE or GNOME also switches `scx_loader` profiles (Power Save / Auto / Gaming).

## ananicy-cpp interactions

Current [CachyOS sched-ext guidance](https://wiki.cachyos.org/configuration/sched-ext/) says `ananicy-cpp` is usually safe alongside scx. Do not disable it preemptively. If a scheduler stalls or becomes unstable, inspect both services and offer disabling Ananicy as a troubleshooting step:

```bash
systemctl status ananicy-cpp scx_loader.service
journalctl -u scx_loader.service -b 0
# With the user's approval:
sudo systemctl disable --now ananicy-cpp
```

`gamemode` and Ananicy both adjust process niceness. Prefer one of them for that role; on CachyOS, `game-performance` integrates with the power-profile and scx stack without replacing the scheduler.

## scx_loader (preferred over raw `sudo scx_rusty`)

```bash
sudo pacman -S scx-scheds scx-tools
# bleeding edge:
# sudo pacman -S scx-scheds-git scx-tools-git

sudo mkdir -p /etc/scx_loader
sudo cp /usr/share/scx_loader/config.toml /etc/scx_loader/config.toml
# NEVER edit /usr/share/scx_loader/config.toml
```

Lookup order: `/etc/scx_loader/config.toml` (preferred), `/etc/scx_loader.toml`, then the `/usr/share` templates.

```toml
default_sched = "scx_lavd"
default_mode = "Auto"

[scheds.scx_lavd]
auto_mode = []
```

```bash
sudo systemctl enable --now scx_loader.service
systemctl status scx_loader.service
journalctl -u scx_loader.service -b 0
```

One-shot tests without the service: `sudo scx_lavd --performance`, then Ctrl+C to return to the in-kernel scheduler. Prefer the loader for anything that should survive reboot.

**Handheld default is `scx_lavd`.** See [`handheld.md`](handheld.md).

BMQ and hardened kernels **cannot** run sched-ext. See [`kernel.md`](kernel.md).

NEVER migrate back to the old `scx.service` / `/etc/default/scx`. If you find them, disable `scx.service` and move flags into `/etc/scx_loader/config.toml`.

## ZRAM and I/O — override, do not edit shipped rules

ZRAM is on by default via CachyOS-Settings.

**NVMe I/O scheduler:** shipped udev sets **kyber**, not `none`. Wiki examples that still show `none` are stale. Verify:

```bash
cat /sys/block/nvme0n1/queue/scheduler
```

**NEVER edit** `/usr/lib/sysctl.d/70-cachyos-settings.conf` or shipped udev rules.

Override:

```
/etc/sysctl.d/99-local.conf
/etc/udev/rules.d/99-local-iosched.rules
```

Then `sudo sysctl --system` or reload udev. Take a snapshot first if you are changing I/O on the root disk.

## Benchmarks (optional)

```bash
sudo pacman -S cachyos-benchmarker schbench
cachyos-benchmarker ~/cachyos-benchmarker/
schbench -m 2 -t 8 -r 60
```

On an `scx_loader` stall: `journalctl --unit scx_loader.service --boot 0 > crash.log`.

## MUST / NEVER

- MUST inspect `ananicy-cpp` and `scx_loader` before changing the scheduler stack.
- MUST treat disabling `ananicy-cpp` as a troubleshooting step for scx, not a prerequisite.
- MUST copy scx config into `/etc/scx_loader/config.toml`, never edit `/usr/share`.
- MUST verify NVMe scheduler live; do not assume `none`.
- NEVER combine `ananicy-cpp` and `gamemode` casually; they both change process priorities.
- NEVER edit `/usr/lib/sysctl.d/70-cachyos-settings.conf`.
- NEVER recommend the RT kernel for gaming ([`kernel.md`](kernel.md)).
