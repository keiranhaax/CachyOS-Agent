# Packaging and contribution

Read this before writing or changing a CachyOS PKGBUILD, choosing a repo, or bumping a `-git` package.

This file is the **only** required path for PKGBUILD-authoring. `SKILL.md` does not replace it.

## Where work lives

- PKGBUILDs: [CachyOS-PKGBUILDS](https://github.com/CachyOS/CachyOS-PKGBUILDS)
- Kernels: [linux-cachyos](https://github.com/CachyOS/linux-cachyos)
- Settings: [CachyOS-Settings](https://github.com/CachyOS/CachyOS-Settings)
- Follow [Arch package guidelines](https://wiki.archlinux.org/title/Arch_package_guidelines) plus Cachy repo conventions.

CachyOS is mostly **GPL-3.0**. NEVER drop MIT-licensed text from other distros into these trees.

```bash
git clone https://github.com/CachyOS/CachyOS-PKGBUILDS.git
cd CachyOS-PKGBUILDS/<pkgdir>
# Prefer these over bare `makepkg -si` when practical:
pkgctl build
# or:
makepkg -Ccfsi
namcap PKGBUILD
namcap *.pkg.tar.zst
pacman -Si <pkg>
```

Wiki preview (when editing wiki sources): `bun install` then `bun run dev`.

README also shows a lowercase `cachyos-pkgbuilds` clone path; the org repo is `CachyOS/CachyOS-PKGBUILDS`.

## Which repo a package belongs in

| Repo | What goes there |
|------|-----------------|
| `[cachyos]` (generic) | Cachy-specific projects: kernels, `chwd`, settings, installer bits, packages that are not ISA rebuilds of Arch. |
| `[cachyos-core-v3/v4/znver4]`, `[cachyos-extra-*]`, `[cachyos-v*]` | ISA rebuilds of Arch `core`/`extra` (and the catch-all ISA repo). `march` matches the repo. |
| Arch `[core]`/`[extra]` | Not where Cachy-optimized rebuilds should be published. |

A package that is only a Cachy patch on top of Arch still needs a clear home: generic `[cachyos]` if it is Cachy-only, ISA extra/core if it is a rebuild the ISA repos are meant to override.

## Build flags

Cachy rebuilds commonly use:

- `-march` for the target ISA (`x86-64-v3`, `x86-64-v4`, `znver4`)
- LTO (often Clang ThinLTO for heavy packages; kernel default is ThinLTO)
- Selected PGO / BOLT where the PKGBUILD already has it

**NEVER invent PGO for a package that Cachy does not already profile.** Look at the existing PKGBUILD and neighboring packages in CachyOS-PKGBUILDS.

`-bin` packages skip this. They are not "optimized Cachy builds". See [`repos.md`](repos.md).

## `-git` cadence

Cachy carries a small set of `-git` packages (for example `mesa-git`, `scx-scheds-git`). FAQ cadence is **usually Monday** (exceptions happen). Follow the existing pkgver scheme in that PKGBUILD. NEVER convert a stable package to `-git` because an agent wants HEAD.

## MUST / NEVER

- MUST state which repo (`cachyos` vs `cachyos-extra-v4` vs …) the package targets.
- MUST keep `march` / LTO / PGO consistent with sibling PKGBUILDs in that repo.
- MUST follow Arch guidelines for naming, splitting, and install files.
- NEVER edit shipped files under `/usr/lib` as a "packaging shortcut" on a running system; that is an overlay, not a package.
- NEVER copy another distro's skill or PKGBUILD prose into this repo.
