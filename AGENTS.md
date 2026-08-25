# CachyOS agent guidance

Agents are first-class on CachyOS. NEVER pick a favorite harness. Skills are guidance, not law: plan, then change, then verify. Prefer rollback (Limine snapshots / snapper) over heroic undo.

This file is for any agent working on or with CachyOS (running install, packaging, docs, or ISO). The umbrella skill primarily assumes a running install; `install.md` and `packaging.md` cover their named pre-install and development workflows. Read the matching topic before touching kernels, repos, schedulers, hardware, boot, desktops, handhelds, or PKGBUILDs.

## Principles

- NEVER treat CachyOS as vanilla Arch. Arch Wiki is background, not the procedure.
- NEVER edit shipped files under `/usr/lib` (for example `/usr/lib/sysctl.d/70-cachyos-settings.conf`). Override in `/etc/sysctl.d/`, `/etc/udev/rules.d/`, `/etc/scx_loader/config.toml`, `/etc/default/limine`.
- When wiki, README, and old articles conflict, do not pick a side. Verify live with `pacman -Si <pkg>` and `kerver`.
- Treat `upstreams.tsv` as a review marker, not proof that prose is current. Run `bin/cachyos-agent-skills-check-upstreams` after CachyOS updates; changed commits require human review against the live system and official sources.
- Plan the change. Take a snapper snapshot when the work is destructive. Apply. Verify. Roll back if it is wrong.
- ALWAYS prefer Cachy tools: Kernel Manager (`cachyos-kernel-manager`), `chwd`, `scx_loader`, `cachyos-repo.sh`, `cachy-chroot`, `game-performance`.

## Skill index

Read the matching topic before starting that class of work:

- [`agents/skills/cachyos/SKILL.md`](agents/skills/cachyos/SKILL.md) — required path, safety, decision framework
- [`agents/skills/cachyos/kernel.md`](agents/skills/cachyos/kernel.md) — `linux-cachyos*` variants, Kernel Manager, modules
- [`agents/skills/cachyos/repos.md`](agents/skills/cachyos/repos.md) — ISA repos, `pacman.conf` order, `cachyos-repo.sh`
- [`agents/skills/cachyos/performance.md`](agents/skills/cachyos/performance.md) — scx, ananicy-cpp, gamemode, ZRAM, `game-performance`
- [`agents/skills/cachyos/hardware.md`](agents/skills/cachyos/hardware.md) — `chwd` profiles, GPU migration, NVIDIA modules
- [`agents/skills/cachyos/boot.md`](agents/skills/cachyos/boot.md) — Limine/snapper, recovery via `cachy-chroot`
- [`agents/skills/cachyos/desktop.md`](agents/skills/cachyos/desktop.md) — `cachyos-*-settings`, `/etc/skel`, Hyprland Noctalia+UWSM
- [`agents/skills/cachyos/install.md`](agents/skills/cachyos/install.md) — ISO, installer, overlay vs conversion
- [`agents/skills/cachyos/packaging.md`](agents/skills/cachyos/packaging.md) — CachyOS-PKGBUILDS, march/LTO/PGO (deep authoring lives only here)
- [`agents/skills/cachyos/handheld.md`](agents/skills/cachyos/handheld.md) — Handheld Edition, `linux-cachyos-deckify`, `scx_lavd`

Install the skill into local harness directories with [`bin/cachyos-provision-agent-skills`](bin/cachyos-provision-agent-skills).

Repository releases and upstream review are documented in [`MAINTENANCE.md`](MAINTENANCE.md). Never auto-rewrite guidance from fetched documentation and never pull Git as root from a pacman hook.
