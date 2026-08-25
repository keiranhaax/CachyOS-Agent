# Prompt for the AI agent on the CachyOS PC

Install the custom `cachyos-agent-system` as a pacman-managed package on this CachyOS computer. Work autonomously within these requirements, preserve existing user data, and stop if the operating system, source, or package cannot be verified.

Requirements:

1. Confirm this is a real CachyOS installation by reading `/etc/os-release`. If it is vanilla Arch with CachyOS repositories rather than CachyOS, stop and explain the distinction.
2. Locate the mounted USB filesystem by its label `CACHYOS_AGENT`. The transfer folder is `cachyos-agent-system` at the USB root. Do not format, repartition, or otherwise modify the USB or any system disk.
3. Change into the USB's `cachyos-agent-system` folder and run `sha256sum -c SHA256SUMS` there. Stop if any listed file is missing or fails verification. The optional prebuilt package is under `dist/` and is covered by that checksum file.
4. Read `README.md`, `AGENTS.md`, `MAINTENANCE.md`, `packaging/README.md`, `packaging/pacman/cachyos-agent.conf`, `PKGBUILD`, and `agents/skills/cachyos/SKILL.md` completely. Confirm `VERSION`, `pkgver`, and the intended Git tag are identical.
5. Confirm that `https://github.com/keiranhaax/CachyOS-Agent` is the configured upstream and that its matching release/tag exists. The pacman repository is personal and currently unsigned: HTTPS and pacman's repository hashes protect transport and detect corruption, but there is no maintainer package-signing key. Report that trust boundary before proceeding.
6. Install the repository fragment as `/etc/pacman.d/cachyos-agent.conf`. Add exactly one line `Include = /etc/pacman.d/cachyos-agent.conf` at the end of `/etc/pacman.conf`; inspect first and do not append a duplicate. Do not change, reorder, or remove any CachyOS/Arch repository.
7. Run one full synchronized transaction: `sudo pacman -Syu cachyos-agent-system`. Do not use `pacman -Sy` by itself and do not install this source by manually copying files into `/usr`.
8. Verify package ownership and layout with `pacman -Qii cachyos-agent-system` and `pacman -Ql cachyos-agent-system`. Confirm:
   - the canonical skill is `/usr/share/cachyos-agent-system/agents/skills/cachyos/SKILL.md`;
   - all three commands are package-owned under `/usr/bin`;
   - the license is under `/usr/share/licenses/cachyos-agent-system`;
   - `bash -n` passes for the three installed commands.
9. Run `cachyos-provision-agent-skills` as the logged-in user, without `sudo` and without `--force` first. It should link the package-owned skill into each supported agent harness. If a regular skill directory already exists, inspect and report it; use `--force` only when it is genuinely a prior `cachyos` skill and its timestamped backup behavior is appropriate.
10. Verify every resulting `cachyos` link resolves to `/usr/share/cachyos-agent-system/agents/skills/cachyos`. No link may point to the USB or a Downloads directory.
11. Run `cachyos-agent-skills-check-upstreams`. If an official upstream branch changed, report that review is required. Do not rewrite guidance automatically and do not change `upstreams.tsv` merely to silence the warning.
12. Verify the update channel without changing unrelated packages: `pacman-conf --repo-list` must include `cachyos-agent`, and `pacman -Si cachyos-agent-system` must show that repository. Future reviewed package releases will then be offered by normal `pacman -Syu`; this does not mean every upstream CachyOS change rewrites the guidance automatically.
13. Restart or reopen the installed AI agent if necessary for skill discovery. Test that `$cachyos` can be invoked, but do not make unrelated system configuration changes.

Finish with a concise report containing the installed version, package/repository verification, canonical destination, links created, validation results, upstream-review status, backup path if one was made, the unsigned-repository warning, and whether automatic package updates are actually configured.
