# Pacman packaging

`PKGBUILD` produces the architecture-independent `cachyos-agent` package. It installs reviewed, immutable source files:

| Where | What |
|---|---|
| `/usr/share/cachyos-agent/` | The data root: `bin/`, `lib/`, `agents/skills/`, `data/`, `shell/`, `VERSION`, `AGENTS.md`, `upstreams.tsv` |
| `/usr/bin/` | A symlink to each command in the data root's `bin/`, plus `cachyos-provision-agent-skills` for the former package |
| `/usr/share/applications/` | `cachyos-agent.desktop` |
| `/usr/lib/systemd/user/` | The user units for the usage timer, the crash watcher and the theme follower. None is enabled |
| `/usr/share/plasma/plasmoids/org.cachyos.agent/` | The panel widget |
| `/usr/share/doc/cachyos-agent/` | `README.md`, `MAINTENANCE.md`, `THIRD_PARTY_NOTICES.md` and this directory's files |
| `/usr/share/licenses/cachyos-agent/` | The GPL license |

The package never writes to a user's home directory and enables nothing. Hard dependencies are what every command needs (`bash`, `jq`, `python`, `coreutils`, `gawk`, `systemd`); each optional dependency names the feature it enables, so a machine without a terminal, libnotify or Ollama still installs. After installation, each user runs:

```bash
cachyos-agent skills provision
```

and then opts in to whatever else they want; the [`README.md`](../README.md) describes each step.

## Local build

Build only from a release tag whose name matches `VERSION` and `pkgver`:

```bash
makepkg -Ccf
namcap PKGBUILD cachyos-agent-[0-9]*.pkg.tar.zst
```

`check()` runs the skill validator and `test/run-tests` on the tagged source. A case that needs a tool the build machine lacks (`git`, `kconfig`, `fish`, `node`, the Qt 6 and Plasma QML modules) prints `skip` or `UNVERIFIED` and still passes. `namcap` reports no errors on the package. Its warnings are expected: the usage collectors import `collectors` from the `lib/` directory beside `bin/`, which `namcap` cannot see, and the widget's QML modules come with `plasma-desktop`, which is an optional dependency.

Install the inspected artifact with `sudo pacman -U ./cachyos-agent-[0-9]*.pkg.tar.zst`.

## Update repository

Pushing a matching `v*` tag runs `.github/workflows/release.yml`. The workflow validates the tree (shellcheck on the Bash files, `py_compile` on the Python ones, the skill validator, isolated tests), builds the package, signs the package and the repository database with the maintainer key, publishes the package, its detached signature, the SHA-256 checksums, and the public signing key on the GitHub release, and updates the `repo` branch's `x86_64/cachyos-agent` database. The repository retains only the newest package version.

## Signing

Releases fail without a signing key. Generate a dedicated key without a passphrase (CI cannot answer pinentry prompts), keep the private key only in the GitHub Actions secret, and rotate it if it may have leaked:

```bash
gpg --quick-generate-key 'cachyos-agent (package signing) <maintainer@example>' ed25519 sign never
gpg --armor --export-secret-keys <fingerprint>   # store as the PACKAGE_SIGNING_KEY repository secret
gpg --armor --export <fingerprint> > cachyos-agent-signing-key.asc
```

The workflow exports the public key as `cachyos-agent-signing-key.asc` on every release and at the `repo` branch root. Publish the fingerprint through a second channel so users can verify the key they import: the root [`README.md`](../README.md) carries a **Signing key fingerprint** line that must be filled in with the real fingerprint in the same commit that is tagged for the first signed release, and updated whenever the key rotates.

## Enroll a machine

To enroll one CachyOS machine, first inspect [`pacman/cachyos-agent.conf`](pacman/cachyos-agent.conf), import and locally sign the maintainer key after verifying its fingerprint, then install the fragment and include it from `/etc/pacman.conf`:

```bash
curl -fsSLO https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/repo/cachyos-agent-signing-key.asc
gpg --show-keys cachyos-agent-signing-key.asc   # verify the fingerprint out of band
sudo pacman-key --add cachyos-agent-signing-key.asc
sudo pacman-key --lsign-key <fingerprint>

sudo install -Dm644 packaging/pacman/cachyos-agent.conf /etc/pacman.d/cachyos-agent.conf
grep -Fxq 'Include = /etc/pacman.d/cachyos-agent.conf' /etc/pacman.conf || \
  printf '\nInclude = /etc/pacman.d/cachyos-agent.conf\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu cachyos-agent
cachyos-agent skills provision
```

Do not append the `Include` line twice. The repository is intentionally below CachyOS and Arch repositories when its include is appended at the end of `pacman.conf`; it contains only this uniquely named package.

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned databases. Releases published before signing was introduced cannot be installed through this repository; install only signed releases.
