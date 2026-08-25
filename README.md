# CachyOS Agent

[![CI](https://github.com/keiranhaax/CachyOS-Agent/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/keiranhaax/CachyOS-Agent/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/keiranhaax/CachyOS-Agent?display_name=tag&sort=semver)](https://github.com/keiranhaax/CachyOS-Agent/releases)
[![License](https://img.shields.io/github/license/keiranhaax/CachyOS-Agent)](LICENSE)

> CachyOS-aware guidance, topic skills, and a signed pacman package for AI agents.

CachyOS Agent gives coding agents reviewed, operational guidance for CachyOS-specific kernels, repositories, schedulers, hardware, boot recovery, desktops, packaging, and handheld systems. It complements the [official CachyOS wiki](https://wiki.cachyos.org/) but is an independent, unofficial project.

## Why this exists

Vanilla Arch advice is actively wrong in several CachyOS-specific areas, including ISA repositories, kernel modules, scheduler integration, Limine/snapper, `chwd`, shipped settings, desktop packages, and handhelds. These files help agents inspect the live system, choose the CachyOS-native path, plan risky work, and verify the result.

Agents are first-class. The project never favors a particular harness, and its skills are guidance rather than unattended authority.

## Quick start

### Recommended: install the signed pacman package

Reviewed tags publish an architecture-independent `cachyos-agent-system` package and a signed pacman repository. Import and locally sign the maintainer key before enabling the repository.

**Signing key fingerprint:** `8A55 9E3B B6EB 0640 1622 73BC C1D6 43CE B30C 6C59`. Verify it out of band and do not trust a key with a different fingerprint. Releases through `v0.1.1` are unsigned and cannot be installed through this repository.

```bash
curl -fsSLO \
  https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/repo/cachyos-agent-signing-key.asc

gpg --show-keys cachyos-agent-signing-key.asc
sudo pacman-key --add cachyos-agent-signing-key.asc
sudo pacman-key --lsign-key 8A559E3BB6EB0640162273BCC1D643CEB30C6C59

curl -fsSLo cachyos-agent.conf \
  https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/main/packaging/pacman/cachyos-agent.conf

sudo install -Dm644 cachyos-agent.conf \
  /etc/pacman.d/cachyos-agent.conf

grep -Fxq 'Include = /etc/pacman.d/cachyos-agent.conf' /etc/pacman.conf || \
  printf '\nInclude = /etc/pacman.d/cachyos-agent.conf\n' | sudo tee -a /etc/pacman.conf

sudo pacman -Syu cachyos-agent-system
cachyos-provision-agent-skills
```

Inspect `/etc/pacman.conf` before changing it and include the repository fragment only once. Package installation updates the canonical files under `/usr/share/cachyos-agent-system/`; it does **not** modify user home directories. Each intended user must run `cachyos-provision-agent-skills` without `sudo`.

See [`packaging/README.md`](packaging/README.md) for the repository trust boundary, signing details, and local-build procedure.

### Install from a Git checkout

Keep the checkout in a stable location so its provisioned links remain valid.

```bash
git clone https://github.com/keiranhaax/CachyOS-Agent.git \
  ~/.local/share/cachyos-agent-system

cd ~/.local/share/cachyos-agent-system
./bin/cachyos-provision-agent-skills
```

Run `./bin/cachyos-provision-agent-skills --help` for source and replacement options.

## What provisioning changes

The provisioner links each directory under `agents/skills/` into every supported agent harness:

| Harness | Path |
|---|---|
| Generic agents | `~/.agents/skills/<name>` |
| Claude | `~/.claude/skills/<name>` |
| Codex | `~/.codex/skills/<name>` |
| Pi | `~/.pi/agent/skills/<name>` |
| Gemini | `~/.gemini/config/skills/<name>` |

Provisioning is idempotent. Without `--force`, existing regular files and directories are left untouched. With `--force`, an existing skill directory is moved to a timestamped sibling backup before its link is created. The provisioner never recursively deletes a skill and refuses sources without `SKILL.md`.

Links from a Git installation track that checkout. Moving the checkout breaks them until the provisioner is run again from the new location. New skill names are also linked only after the provisioner is rerun.

## Topic guides

| Guide | Purpose |
|---|---|
| [`SKILL.md`](agents/skills/cachyos/SKILL.md) | Required safety path and decision framework for CachyOS work. |
| [`kernel.md`](agents/skills/cachyos/kernel.md) | `linux-cachyos*` variants, Kernel Manager, and matching modules. |
| [`repos.md`](agents/skills/cachyos/repos.md) | ISA repositories, ordering, mirrorlists, and migrations. |
| [`performance.md`](agents/skills/cachyos/performance.md) | sched-ext, Ananicy, GameMode, ZRAM, and I/O tuning. |
| [`hardware.md`](agents/skills/cachyos/hardware.md) | `chwd` profiles, GPU migrations, and NVIDIA modules. |
| [`boot.md`](agents/skills/cachyos/boot.md) | Limine, snapper snapshots, recovery, and `cachy-chroot`. |
| [`desktop.md`](agents/skills/cachyos/desktop.md) | Packaged desktop defaults, `/etc/skel`, Noctalia, and UWSM. |
| [`install.md`](agents/skills/cachyos/install.md) | ISO choices, installation, and Arch repository overlays. |
| [`packaging.md`](agents/skills/cachyos/packaging.md) | CachyOS PKGBUILDs, repository choice, march, LTO, and PGO. |
| [`handheld.md`](agents/skills/cachyos/handheld.md) | Handheld Edition, deckify kernels, and `scx_lavd`. |

## Safety model

1. Inspect the live system before changing it.
2. Treat CachyOS as different from vanilla Arch.
3. Plan destructive changes before applying them.
4. Take a snapper snapshot before destructive work.
5. Prefer CachyOS tools and installed package data.
6. Verify after every change.
7. Never edit shipped files under `/usr/lib`.
8. Never pull and execute arbitrary Git changes from a root pacman hook.

Prefer rollback through Limine snapshots or snapper over heroic undo. When published sources disagree, verify against the running system with tools such as `pacman -Si`, `kerver`, and `chwd`.

## Updates and freshness

Pacman installations receive reviewed releases through normal `pacman -Syu` transactions. Git installations can run `./bin/cachyos-agent-skills-update`, which permits only a clean fast-forward update and refuses dirty or divergent trees.

Run `./bin/cachyos-agent-skills-check-upstreams` after a CachyOS update or before publishing a release. It detects relevant upstream movement for human review; it never treats a changed commit hash as proof that guidance is still correct and never rewrites guidance automatically.

## Validate and develop

Run the release checks natively on CachyOS or Arch with GNU userland:

```bash
./bin/cachyos-agent-skills-validate
./test/run-tests
shellcheck bin/* test/run-tests
namcap PKGBUILD
```

See [`MAINTENANCE.md`](MAINTENANCE.md) for the complete upstream-review and release checklist.

<details>
<summary>Repository layout</summary>

```text
AGENTS.md                         Philosophy and topic index
MAINTENANCE.md                    Upstream review and release checklist
THIRD_PARTY_NOTICES.md            Omarchy attribution and MIT notice
VERSION upstreams.tsv LICENSE    Version, reviewed sources, and project license
agents/skills/cachyos/            Umbrella skill and CachyOS topic guides
bin/cachyos-provision-agent-skills
bin/cachyos-agent-skills-update
bin/cachyos-agent-skills-check-upstreams
bin/cachyos-agent-skills-validate
test/run-tests                    Isolated provisioner, validator, and package tests
PKGBUILD .SRCINFO                 Arch/CachyOS package recipe and metadata
packaging/                        Pacman repository configuration and release notes
.github/workflows/ci.yml          Validation on every push and pull request
.github/workflows/release.yml     Signed package and repository publication
```

</details>

## Acknowledgements

CachyOS Agent was inspired by [Omarchy's agent-friendly architecture](https://github.com/basecamp/omarchy/tree/quattro), particularly its `AGENTS.md` conventions, skill organization, and multi-agent provisioning approach. Omarchy was created by [David Heinemeier Hansson](https://github.com/dhh) and is distributed under the MIT License.

CachyOS Agent is an independent project and is not affiliated with or endorsed by Omarchy, Basecamp, or CachyOS. The complete upstream notice is preserved in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## License

Original CachyOS Agent code and guidance are licensed under GPL-3.0-only; see [`LICENSE`](LICENSE). Omarchy's separate MIT notice is preserved in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
