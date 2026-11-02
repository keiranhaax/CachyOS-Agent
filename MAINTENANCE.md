# Maintenance and releases

This project contains reviewed operational guidance, not generated documentation. Upstream changes can be detected automatically, but their meaning must be reviewed before changing agent instructions.

## Source and installation model

- Keep the canonical project in a versioned Git repository.
- Keep personal checkouts in a stable path such as `~/.local/share/cachyos-agent`, never a temporary download directory.
- For system-managed installations, publish a package in a pacman repository already configured on the target machine. Install project data under `/usr/share/cachyos-agent/`, the `bin/` commands under `/usr/bin`, and the license under `/usr/share/licenses/cachyos-agent/`.
- Do not make package hooks fetch Git or rewrite skills. A package update must contain already-reviewed files.
- `PKGBUILD`, `VERSION`, and the release tag must carry the same semantic version. Increment `pkgrel` only for packaging-only changes to the same source version.
- `bin/` holds Bash commands only: the lint step runs `shellcheck` on every file there and fails on anything else. Python helpers live in `lib/` and are run by a Bash command. `cachyos-agent skills validate` syntax-checks `lib/*.sh` and `lib/*.py`.
- A command calls a sibling as `"$CACHYOS_AGENT_BIN/cachyos-agent-<name>"` (set by `lib/common.sh`), never by bare name: `PATH` may lack the package or hold an older copy.

## Upstream review

Run:

```bash
./bin/cachyos-agent-skills-check-upstreams
```

If any branch changed, review the relevant diffs and current live behavior. At minimum, verify:

1. Current desktop and handheld ISO identifiers and supported hardware.
2. Kernel variants, schedulers, preemption, and prebuilt module names.
3. Optimized repository names, ordering, mirrorlists, and migration commands.
4. `scx_loader`, Ananicy, GameMode, power-profile, ZRAM, and I/O scheduler guidance.
5. `chwd` commands and current profile names.
6. Limine, snapper, boot-manager, and `cachy-chroot` procedures.
7. Current desktop settings packages, Hyprland/Noctalia paths, and UWSM behavior.
8. CLI-installer schema and the live `server-profiles.toml` values.

Use the running system (`pacman -Si`, `pacman -Ql`, `kerver`, `chwd --help`) when published sources disagree. Update `upstreams.tsv` only after completing the review; a new commit hash is not evidence that the existing guidance remains correct.

Rows in `upstreams.tsv` may carry a fifth column of space-separated paths that scope the review trigger to the files the guidance actually cites. When the checker reports `current in scope` (the head moved but no in-scope commit exists), the reviewed commit may be fast-forwarded to the new head without a full re-review. Widen a row's scope whenever a skill starts relying on new upstream files; a too-narrow scope silently hides relevant changes.

## Release checklist

1. Update the affected skill files and the reviewed commits in `upstreams.tsv`.
2. Increment `VERSION` using semantic versioning.
3. Run `./bin/cachyos-agent-skills-validate`, `shellcheck -x bin/* lib/*.sh test/run-tests test/lib.sh test/cases/*.sh`, and `./test/run-tests`. CI runs the same checks on every push and pull request, and the release workflow repeats them before building.
4. Update `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO` and review the diff.
5. Confirm the `PACKAGE_SIGNING_KEY` repository secret holds the current maintainer signing key; the release fails without it. Confirm the **Signing key fingerprint** line in `README.md` matches that key. Key generation and rotation are documented in [`packaging/README.md`](packaging/README.md).
6. Commit, then tag the exact commit as `v<VERSION>`. Never move a published release tag.
7. Push the branch and tag. The release workflow builds as an unprivileged user, runs `namcap`, signs the package and the repository database, publishes the artifact, its signature, the checksum, and the public key, and updates the `repo` branch.
8. Verify the GitHub Actions run and test `pacman -Syu cachyos-agent` from an enrolled CachyOS machine. Test the upgrade from the previous release, not only a fresh install, and confirm a skill link made by that release still resolves. The compatibility names in `PKGBUILD` (`/usr/share/cachyos-agent-system`, `/usr/bin/cachyos-provision-agent-skills`) stay until a release that says in its notes that they are gone.

Do not claim that every CachyOS update automatically changes this prose. The dependable guarantee is that upstream movement is detected, reviewed releases are published, and pacman installs those reviewed releases.
