# CachyOS agent guidance

Use these files when an agent must modify or reason about a CachyOS machine.

This is not a second documentation tree. The [wiki](https://wiki.cachyos.org/) is the human reference. These files exist because vanilla Arch advice is actively wrong in several Cachy-specific places (ISA repos, kernels and matching modules, scheduler integration, Limine/snapper, `chwd`, shipped settings, DE packages, handheld).

Agents are first-class. NEVER pick a favorite harness. Treat the skill as guidance, not law: plan first, then change, then verify. Prefer rollback (Limine snapshots / snapper) over heroic undo.

## Layout

```
AGENTS.md                         Philosophy + index (any agent, any Cachy work)
MAINTENANCE.md                    Upstream review + package release checklist
VERSION upstreams.tsv LICENSE    Version, reviewed source heads, license
agents/skills/cachyos/            One shipped umbrella skill + topic files
  SKILL.md                        Required path, safety, decision framework
  kernel.md repos.md performance.md hardware.md
  boot.md desktop.md install.md packaging.md handheld.md
bin/cachyos-provision-agent-skills
bin/cachyos-agent-skills-update
bin/cachyos-agent-skills-check-upstreams
bin/cachyos-agent-skills-validate
test/run-tests                    Isolated provisioner and validator tests
PKGBUILD                          Arch/CachyOS pacman package recipe
packaging/                       Pacman repository template and release notes
.github/workflows/ci.yml         Shellcheck, validator, tests on every push/PR
.github/workflows/release.yml    Tagged signed package/repository release automation
```

`AGENTS.md` is repository-level guidance. The umbrella skill primarily manages a running CachyOS install and routes installation planning and packaging work to their dedicated topic files.

## Install with pacman

Reviewed tags produce an architecture-independent `cachyos-agent-system` package. Packages and the repository database are signed; import and locally sign the maintainer key first (fingerprint verification and key handling are documented in [`packaging/README.md`](packaging/README.md)). Then install the repository fragment, include it once from `/etc/pacman.conf`, and install normally.

**Signing key fingerprint:** _not yet published — the first signed release is `v0.1.2`. The maintainer records the fingerprint here when that release is tagged. Do not trust a key whose fingerprint does not match this line._ Releases up to and including `v0.1.1` are unsigned and cannot be installed through this repository.

```bash
curl -fsSLO https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/repo/cachyos-agent-signing-key.asc
gpg --show-keys cachyos-agent-signing-key.asc   # verify the fingerprint out of band
sudo pacman-key --add cachyos-agent-signing-key.asc
sudo pacman-key --lsign-key <fingerprint>

sudo install -Dm644 packaging/pacman/cachyos-agent.conf /etc/pacman.d/cachyos-agent.conf
grep -Fxq 'Include = /etc/pacman.d/cachyos-agent.conf' /etc/pacman.conf || \
  printf '\nInclude = /etc/pacman.d/cachyos-agent.conf\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu cachyos-agent-system
cachyos-provision-agent-skills
```

Inspect `/etc/pacman.conf` first and do not add the `Include` line twice. The package does not modify home directories automatically; run the provisioner as each intended user. See [`packaging/README.md`](packaging/README.md) for the repository trust boundary and local-build procedure.

## Install from a personal checkout

Keep the source in a stable location, not in `~/Downloads`. For a personal checkout, `~/.local/share/cachyos-agent-system` is a suitable location. From that checkout:

```bash
./bin/cachyos-provision-agent-skills
./bin/cachyos-provision-agent-skills --help
```

The script `ln -sfn`s every subdirectory of `agents/skills/` into:

- `~/.agents/skills/<name>`
- `~/.claude/skills/<name>`
- `~/.codex/skills/<name>`
- `~/.pi/agent/skills/<name>`
- `~/.gemini/config/skills/<name>`

It is idempotent. Existing regular files or directories are left alone unless you pass `--force`. When replacement is allowed, `--force` moves the old skill directory to a timestamped sibling backup before linking the new one; it never recursively deletes a skill. Anything without `SKILL.md` is refused.

**Contents** track this checkout because they are symlinks. **New skill names** (a new directory under `agents/skills/`) are picked up only after you re-run the script. Moving the checkout breaks the links; run the script again from the new path.

The script also recognizes the package-owned source at `/usr/share/cachyos-agent-system/agents/skills`. Package upgrades refresh those symlink targets through normal `pacman -Syu` transactions.

## Updates and freshness

There are two supported source models:

- **Pacman package:** publish reviewed releases in a repository configured on the machine. `pacman -Syu` updates the canonical files under `/usr/share/cachyos-agent-system/`.
- **Git checkout:** keep a clean checkout in a stable location and run `./bin/cachyos-agent-skills-update`. It only performs a fast-forward update and refuses dirty or divergent trees.

Run `./bin/cachyos-agent-skills-check-upstreams` after a CachyOS system update or before publishing a release. It compares the reviewed commits in `upstreams.tsv` with the official repositories. Rows may scope that comparison to the upstream paths the guidance actually cites, so unrelated upstream churn does not raise review noise. An in-scope change means **review is required**; it does not mean prose can be rewritten automatically. Do not use a root pacman hook to pull and execute arbitrary Git changes.

Run `./bin/cachyos-agent-skills-validate` before committing skill changes; it checks frontmatter, relative links, and index consistency between `AGENTS.md` and the skill files. `./test/run-tests` exercises the provisioner and validator in an isolated temporary home. CI runs both on every push and pull request.

See [`MAINTENANCE.md`](MAINTENANCE.md) for the release checklist.

## Use

1. Provision the skill (above).
2. Inspect the live system and plan system-wide or destructive changes.
3. Take a snapper snapshot before destructive changes (`boot.md`).
4. Apply, then verify (`pacman -Si`, `kerver`, `chwd --list`, the topic file's checks).
5. Roll back from Limine snapshots if it is wrong.

If an agent treats CachyOS as vanilla Arch, STOP and point it at `SKILL.md`.

## License

Copyright (C) 2026 the cachyos-agent-system contributors. Licensed under GPL-3.0-only; see [`LICENSE`](LICENSE). CachyOS is a separate project and is not the publisher of this custom skill package.
