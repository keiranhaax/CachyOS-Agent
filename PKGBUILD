# Maintainer: keiranhaax <widisberto@hotmail.com>

pkgname=cachyos-agent-system
pkgver=0.1.3
pkgrel=1
pkgdesc='CachyOS-specific guidance for AI coding agents'
arch=('any')
url='https://github.com/keiranhaax/CachyOS-Agent'
license=('GPL-3.0-only')
depends=('bash')
makedepends=('git')
optdepends=('git: update Git-backed checkouts and check reviewed CachyOS upstreams')
install=cachyos-agent-system.install
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
  local script name

  install -d "$datadir/agents/skills"
  cp -a agents/skills/cachyos "$datadir/agents/skills/"
  install -Dm644 AGENTS.md "$datadir/AGENTS.md"
  install -Dm644 VERSION "$datadir/VERSION"
  install -Dm644 upstreams.tsv "$datadir/upstreams.tsv"

  # AGENTS.md links bin/, MAINTENANCE.md, and (via MAINTENANCE.md) packaging/.
  # Keep those references resolvable beside the data files with relative
  # symlinks so the validator passes against the installed tree.
  install -d "$datadir/bin"
  for script in bin/*; do
    name=${script##*/}
    install -Dm755 "$script" "$pkgdir/usr/bin/$name"
    ln -s "../../../bin/$name" "$datadir/bin/$name"
  done

  install -Dm644 README.md "$docdir/README.md"
  install -Dm644 MAINTENANCE.md "$docdir/MAINTENANCE.md"
  install -Dm644 THIRD_PARTY_NOTICES.md "$docdir/THIRD_PARTY_NOTICES.md"
  install -Dm644 packaging/README.md "$docdir/packaging/README.md"
  install -Dm644 packaging/pacman/cachyos-agent.conf "$docdir/packaging/pacman/cachyos-agent.conf"
  ln -s "../doc/$pkgname/MAINTENANCE.md" "$datadir/MAINTENANCE.md"
  ln -s "../doc/$pkgname/packaging" "$datadir/packaging"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
