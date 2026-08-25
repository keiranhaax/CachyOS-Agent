# Pacman packaging

`PKGBUILD` produces the architecture-independent `cachyos-agent-system` package. It installs reviewed, immutable source files under `/usr/share/cachyos-agent-system`, executable helpers under `/usr/bin`, documentation under `/usr/share/doc/cachyos-agent-system`, and the GPL license under `/usr/share/licenses/cachyos-agent-system`.

The package never writes to a user's home directory. After installation, each user runs:

```bash
cachyos-provision-agent-skills
```

## Local build

Build only from a release tag whose name matches `VERSION` and `pkgver`:

```bash
makepkg -Ccf
namcap PKGBUILD cachyos-agent-system-*.pkg.tar.zst
```

Install the inspected artifact with `sudo pacman -U ./cachyos-agent-system-*.pkg.tar.zst`.

## Update repository

Pushing a matching `v*` tag runs `.github/workflows/release.yml`. The workflow validates and builds the package, publishes the package and its SHA-256 checksum on the GitHub release, and updates the `repo` branch's `x86_64/cachyos-agent` database. The repository retains only the newest package version.

To enroll one CachyOS machine, first inspect [`pacman/cachyos-agent.conf`](pacman/cachyos-agent.conf), then install it and include it from `/etc/pacman.conf`:

```bash
sudo install -Dm644 packaging/pacman/cachyos-agent.conf /etc/pacman.d/cachyos-agent.conf
grep -Fxq 'Include = /etc/pacman.d/cachyos-agent.conf' /etc/pacman.conf || \
  printf '\nInclude = /etc/pacman.d/cachyos-agent.conf\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu cachyos-agent-system
cachyos-provision-agent-skills
```

Do not append the `Include` line twice. The repository is intentionally below CachyOS and Arch repositories when its include is appended at the end of `pacman.conf`; it contains only this uniquely named package.

Packages are currently unsigned because this project has no maintainer signing key. `SigLevel = Optional TrustedOnly` accepts unsigned artifacts while rejecting invalid signatures. Before this repository is used by anyone other than its owner, create and securely manage a package-signing key, sign packages and the database, publish the public key, and change the repository to require signatures.
