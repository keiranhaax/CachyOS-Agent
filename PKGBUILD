# Maintainer: keiranhaax <widisberto@hotmail.com>

pkgname=cachyos-agent
pkgver=0.2.0
pkgrel=1
pkgdesc='CachyOS agent runtime and skills for AI coding agents'
arch=('any')
url='https://github.com/keiranhaax/CachyOS-Agent'
license=('GPL-3.0-only')
depends=('bash' 'jq' 'python' 'coreutils' 'systemd')
makedepends=('git')
optdepends=('libnotify: desktop notifications for crash capture'
            'konsole: terminal for launched agents'
            'alacritty: terminal for launched agents'
            'kconfig: Plasma global shortcut and theme sync helpers'
            'plasma-desktop: agents panel widget'
            'ollama: run local models for your agents'
            'paru: install AUR-packaged agents'
            'git: update Git checkouts and check reviewed CachyOS upstreams')
provides=('cachyos-agent-system')
conflicts=('cachyos-agent-system')
replaces=('cachyos-agent-system')
install=cachyos-agent.install
source=("$pkgname::git+$url.git#tag=v$pkgver")
b2sums=('SKIP')

check() {
  cd "$pkgname"

  [[ $(<VERSION) == "$pkgver" ]]

  bash bin/cachyos-agent-skills-validate .
  bash test/run-tests
}

package() {
  cd "$pkgname"

  local datadir="$pkgdir/usr/share/$pkgname"
  local docdir="$pkgdir/usr/share/doc/$pkgname"
  local dir script name

  # lib/common.sh finds the data root by resolving the script's real path, so
  # the real files live under the data root and /usr/bin holds only symlinks.
  install -d "$pkgdir/usr/bin"
  for script in bin/*; do
    name=${script##*/}
    install -Dm755 "$script" "$datadir/bin/$name"
    ln -s "../share/$pkgname/bin/$name" "$pkgdir/usr/bin/$name"
  done
  ln -s cachyos-agent-skills-provision "$pkgdir/usr/bin/cachyos-provision-agent-skills"

  # Whole directories, so a new feature needs no PKGBUILD edit.
  for dir in lib agents shell data; do
    if [[ -d $dir ]]; then
      cp -a "$dir" "$datadir/"
    fi
  done
  if [[ -d desktop ]]; then
    install -Dm644 -t "$pkgdir/usr/share/applications" desktop/*.desktop
  fi
  if [[ -d systemd/user ]]; then
    install -Dm644 -t "$pkgdir/usr/lib/systemd/user" systemd/user/*
  fi
  if [[ -d plasmoid ]]; then
    install -d "$pkgdir/usr/share/plasma/plasmoids"
    cp -a plasmoid/. "$pkgdir/usr/share/plasma/plasmoids/"
  fi

  install -Dm644 AGENTS.md "$datadir/AGENTS.md"
  install -Dm644 VERSION "$datadir/VERSION"
  install -Dm644 upstreams.tsv "$datadir/upstreams.tsv"

  install -Dm644 README.md "$docdir/README.md"
  install -Dm644 MAINTENANCE.md "$docdir/MAINTENANCE.md"
  install -Dm644 THIRD_PARTY_NOTICES.md "$docdir/THIRD_PARTY_NOTICES.md"
  install -Dm644 packaging/README.md "$docdir/packaging/README.md"
  install -Dm644 packaging/pacman/cachyos-agent.conf "$docdir/packaging/pacman/cachyos-agent.conf"
  # AGENTS.md links MAINTENANCE.md and (via MAINTENANCE.md) packaging/. Keep
  # them resolvable beside the data files with relative symlinks so the
  # validator passes against the installed tree.
  ln -s "../doc/$pkgname/MAINTENANCE.md" "$datadir/MAINTENANCE.md"
  ln -s "../doc/$pkgname/packaging" "$datadir/packaging"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
