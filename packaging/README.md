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

Pushing a matching `v*` tag runs `.github/workflows/release.yml`. The workflow validates the tree (shellcheck, skill validator, isolated tests), builds the package, signs the package and the repository database with the maintainer key, publishes the package, its detached signature, the SHA-256 checksums, and the public signing key on the GitHub release, and updates the `repo` branch's `x86_64/cachyos-agent` database. The repository retains only the newest package version.

## Signing

Releases fail without a signing key. Generate a dedicated key without a passphrase (CI cannot answer pinentry prompts), keep the private key only in the GitHub Actions secret, and rotate it if it may have leaked:

```bash
gpg --quick-generate-key 'cachyos-agent-system (package signing) <maintainer@example>' ed25519 sign never
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
sudo pacman -Syu cachyos-agent-system
cachyos-provision-agent-skills
```

Do not append the `Include` line twice. The repository is intentionally below CachyOS and Arch repositories when its include is appended at the end of `pacman.conf`; it contains only this uniquely named package.

`SigLevel = Required DatabaseRequired` rejects unsigned packages and unsigned databases. Releases published before signing was introduced cannot be installed through this repository; install only signed releases.
