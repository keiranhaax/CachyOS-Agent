# Maintainer: keiranhaax <widisberto@hotmail.com>

pkgname=cachyos-agent-system
pkgver=0.1.1
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
  local script

  install -d "$datadir/agents/skills"
  cp -a agents/skills/cachyos "$datadir/agents/skills/"
  install -Dm644 AGENTS.md "$datadir/AGENTS.md"
  install -Dm644 VERSION "$datadir/VERSION"
  install -Dm644 upstreams.tsv "$datadir/upstreams.tsv"

  for script in bin/*; do
    install -Dm755 "$script" "$pkgdir/usr/bin/${script##*/}"
  done

  install -Dm644 README.md "$docdir/README.md"
  install -Dm644 MAINTENANCE.md "$docdir/MAINTENANCE.md"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
