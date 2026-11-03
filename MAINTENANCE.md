# Maintenance and releases

This project contains reviewed operational guidance, not generated documentation. Upstream changes can be detected automatically, but their meaning must be reviewed before changing agent instructions.

## Source and installation model

- Keep the canonical project in a versioned Git repository.
- Keep personal checkouts in a stable path such as `~/.local/share/cachyos-agent`, never a temporary download directory.
- For system-managed installations, publish a package in a pacman repository already configured on the target machine. Install project data under `/usr/share/cachyos-agent/`, the `bin/` commands under `/usr/bin`, and the license under `/usr/share/licenses/cachyos-agent/`.
- Do not make package hooks fetch Git or rewrite skills. A package update must contain already-reviewed files.
- `PKGBUILD`, `VERSION`, and the release tag must carry the same semantic version. Increment `pkgrel` only for packaging-only changes to the same source version.
- `bin/` holds the commands as real files. The package installs them under `/usr/share/cachyos-agent/bin` and links them from `/usr/bin`, because `lib/common.sh` finds the data root from a script's real path.
- Commands are Bash and are checked with `shellcheck`. The few Python commands (the usage collectors and `cachyos-agent-account-state`) start with `#!/usr/bin/python3`, use only the standard library, and are checked with `py_compile`. Their shared module is `lib/collectors.py`. `cachyos-agent skills validate` syntax-checks every file in `bin/`, `lib/*.sh` and `lib/*.py`.
- A command calls a sibling by bare name, as in `cachyos-agent-launch --prompt "$prompt"`. `lib/common.sh` appends the data root's `bin/` to `PATH`, so a checkout works before it is installed, a test stub placed first on `PATH` stands in for the sibling, and a packaged command runs the `/usr/bin` copies. Never build a path to a sibling.
- The package installs no user state and enables nothing. Every unit, shortcut and timer is an opt-in a user turns on with a command (`usage schedule on`, `crash capture on`, `theme follow on`, `shortcut set`).

## Layout

| Path | Holds | Installed to |
|---|---|---|
| `bin/` | The commands, `cachyos-agent` (the dispatcher) and `cachyos-agent-<group>-<name>` | `/usr/share/cachyos-agent/bin`, linked from `/usr/bin` |
| `lib/` | `common.sh`, a `<feature>.sh` helper for a feature that needs one, and `collectors.py` | `/usr/share/cachyos-agent/lib` |
| `agents/skills/` | The `cachyos` and `diagnose-crash` skills | `/usr/share/cachyos-agent/agents/skills` |
| `data/` | Theme templates, the local model recipes, the Pi extension | `/usr/share/cachyos-agent/data` |
| `shell/` | The `a`, `c`, `cx` and `cy` functions for bash and fish | `/usr/share/cachyos-agent/shell` |
| `desktop/` | The desktop entry | `/usr/share/applications` |
| `systemd/user/` | The user units | `/usr/lib/systemd/user` |
| `plasmoid/org.cachyos.agent/` | The panel widget | `/usr/share/plasma/plasmoids/org.cachyos.agent` |
| `test/` | `run-tests`, `lib.sh`, `cases/NN-<feature>.sh`, and the QML harness for the widget | not installed |
| `packaging/`, `PKGBUILD`, `.github/` | Pacman repository, package recipe, CI | `packaging/` goes to the package documentation |

`PKGBUILD` copies whole directories, so a new file inside one of them needs no `PKGBUILD` edit.

## Adding or changing a command

1. Name the file `bin/cachyos-agent-<group>[-<name>[-<sub>]]`, executable, a real file. The first dash after `cachyos-agent-` becomes a space in the route (`cachyos-agent-crash-mute` is `cachyos-agent crash mute`) and later dashes stay in the name. After the prefix the name may hold only letters, digits, `_` and `-`: no dots and no `.py`. `commands` and `version` are reserved groups.
2. Line 1 is `#!/bin/bash` and line 2 is `# SPDX-License-Identifier: GPL-3.0-only`. A file ported from Omarchy has `# Adapted from Omarchy <path> (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md` on line 3 and a row in `THIRD_PARTY_NOTICES.md`; `test/cases/85-docs.sh` fails when the two disagree. Then `set -euo pipefail`, or `set -uo pipefail` where a pipeline must keep running, with a comment that says why.
3. Within the first 80 lines add `# cachyos-agent:summary=...` (required unless the command is hidden), `# cachyos-agent:args=...`, `# cachyos-agent:examples=one | two` (separated by exactly ` | `) and, for a plumbing command, `# cachyos-agent:hidden=true`. `cachyos-agent commands --json` and the group help are built from these lines.
4. Source `lib/common.sh` with `source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/common.sh"`, which only works from a real file under `bin/`, and use its helpers (`ca_die`, `ca_notify`, `ca_flag`, `ca_terminal_exec`, `ca_atomic_write`) instead of writing new ones.
5. A group that is a single command receives `--help` itself when it is the command's first argument, so implement `--help` and `-h`. The dispatcher answers `--help` for a group with subcommands, and `--help` or `-h` anywhere later in a visible command's arguments (before a `--`), where it would otherwise be taken as a value or a label and the command would run; a hidden command gets its arguments untouched.
6. Add a case to `test/cases/NN-<feature>.sh` (or a new one) that runs the command through `bin/cachyos-agent`, in a sandbox from `test/lib.sh`, with stubs for every external program. A case never touches the real home directory, the network, root, a display, or a real agent CLI. Write the case first and watch it fail.
7. Update the guide the command belongs to: `agents/skills/cachyos/agent.md` for how an agent should use it, and the user guide in `README.md`. The command table in `README.md` is generated, and `test/cases/85-docs.sh` fails when it differs from `cachyos-agent commands`. Print the rows to paste with:

```bash
./bin/cachyos-agent commands --json | jq -r '.commands[] | "| `\(.route)` | \(.summary) |"'
```

A new agent in `lib/launcher.sh` also needs a row in the agent table, whose flags and package the same case compares with the launcher and the installer.

Privileged work stays visible: a command runs `sudo` only inside a terminal the user opened, never with `--noconfirm`, never through `pkexec`, and never from a timer or a watcher.

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

## Omarchy

The agent runtime is adapted from Omarchy at the commit named in `THIRD_PARTY_NOTICES.md`. Nothing follows Omarchy automatically. To take a change, compare the origin path of the file you care about (the notices table gives it) at the new Omarchy commit, port what applies to CachyOS and Plasma, and change the commit in the notices only when the whole port has been compared.

Two data files are checked by hand against the vendors, not against Omarchy. The agent flags and install commands in `bin/cachyos-agent-launch` and `bin/cachyos-agent-install` come from each vendor's documentation, so run `<agent> --help` for an agent you can install before you change them. The recipes in `data/local-models.tsv` name Ollama library tags: open `https://ollama.com/library/<model>/tags` for each one before you change a tag or a size.

## Release checklist

1. Update the affected skill files and the reviewed commits in `upstreams.tsv`.
2. Increment `VERSION` using semantic versioning.
3. Run the checks below. CI runs them on every push and pull request, and the release workflow repeats them before building.

   ```bash
   ./bin/cachyos-agent-skills-validate
   ./bin/cachyos-agent commands --check
   ./test/run-tests
   shellcheck -x $(grep -lE '^#!/bin/bash' bin/*) lib/*.sh test/run-tests test/lib.sh test/cases/*.sh
   python3 -I -X pycache_prefix=$(mktemp -d) -m py_compile $(grep -lE '^#!/usr/bin/(env )?python' bin/*) lib/*.py
   namcap PKGBUILD
   ```

   The `grep -lE` keeps `shellcheck` off the Python commands, and the bytecode prefix keeps `__pycache__` out of `bin/`. A case whose tool is missing prints `skip` or `UNVERIFIED` and still passes. Install `gawk kconfig desktop-file-utils fish nodejs` (and the Qt 6 and Plasma modules for the widget) on the machine that tags a release, and read the output for those words.
4. Update `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO` and review the diff.
5. Confirm the `PACKAGE_SIGNING_KEY` repository secret holds the current maintainer signing key; the release fails without it. Confirm the **Signing key fingerprint** line in `README.md` matches that key. Key generation and rotation are documented in [`packaging/README.md`](packaging/README.md).
6. Commit, then tag the exact commit as `v<VERSION>`. Never move a published release tag.
7. Push the branch and tag. The release workflow builds as an unprivileged user, runs `namcap`, signs the package and the repository database, publishes the artifact, its signature, the checksum, and the public key, and updates the `repo` branch.
8. Verify the GitHub Actions run and test `pacman -Syu cachyos-agent` from an enrolled CachyOS machine. Test the upgrade from the previous release, not only a fresh install, and confirm a skill link made by that release still resolves. The compatibility names in `PKGBUILD` (`/usr/share/cachyos-agent-system`, `/usr/bin/cachyos-provision-agent-skills`) stay until a release that says in its notes that they are gone.

Do not claim that every CachyOS update automatically changes this prose. The dependable guarantee is that upstream movement is detected, reviewed releases are published, and pacman installs those reviewed releases.
