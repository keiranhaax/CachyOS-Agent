# Installation and images

Read this before choosing an ISO, running the installer, or "converting" an Arch box to CachyOS.

Facts below are for the **desktop ISO 260809** (26.08) line. Handheld images are versioned separately — do not assume they share that id. Verify the download page if you are on a newer ISO.

## Images

| Image | What it is |
|-------|------------|
| Desktop ISO | Live session is **KDE only**. Calamares installer offers **17+ desktops**. Default bootloader Limine + snapshots on Btrfs. |
| Handheld ISO | **Separate product.** `linux-cachyos-deckify` + `scx_lavd` + gamescope session. See [`handheld.md`](handheld.md). |
| Server | **Experimental CLI profiles** as of ISO 26.08. Not a polished "CachyOS Server" product. |
| Offline / minimal ISO | **None.** Offline installer was dropped. There is no official minimal ISO. |

**NEVER** tell someone to download a "CachyOS minimal" or "offline" image.

Desktop vs handheld is a product choice, not a package you add later. NEVER put Handheld Edition on a tower, or the desktop ISO on a Deck, without following handheld docs.

## Installers

- GUI: Calamares from the live ISO ("Launch Installer").
- CLI: `cachyos-installer` on the live system when you want the non-GUI path.

Unattended / config-driven (from [New-Cli-Installer](https://github.com/CachyOS/New-Cli-Installer) source — **not** the wiki or the repo README):

```bash
sudo cachyos-installer --config /path/to/settings.json
# default if omitted: ./settings.json
cachyos-installer --help
```

- `headless_mode: true` is unattended (`src/main.cpp`).
- Prefer `server_profile`. The parser still accepts `server_mode` but warns it is deprecated and maps a bare `server_mode: true` to `server_profile: "minimal"` (`installer-lib/src/installer_config.cpp`).
- Current profiles live in `server-profiles.toml` (as of that tree: `minimal`, `web`, `container-host`, `cockpit`). There is **no `db` profile**. **Re-read the current TOML and `--help` before writing JSON.**
- Server profile requires `ssh_authorized_keys` and MUST NOT set `desktop`.
- The sample `settings.json` uses `user_pass` and `root_pass` (aliases `user_password` / `root_password`). **NEVER commit JSON that contains those fields** (or `zfs_passphrase`).
- Unknown keys are rejected.

Btrfs + snapper is the path that matches [`boot.md`](boot.md). Other filesystems work; they do not get Limine snapshot integration.

## Existing Arch is a repo overlay, not a conversion

`cachyos-repo.sh` (see [`repos.md`](repos.md)) adds Cachy keys, mirrorlists, and repos. After that you can install `linux-cachyos`, `chwd`, settings packages, etc.

That machine is **Arch with Cachy repos**, not a CachyOS install. It will not have the ISO's Calamares-chosen DE profile, Limine/snapper defaults, or handheld session unless you add those pieces yourself.

**NEVER** call `cachyos-repo.sh` a "migration to CachyOS". Say "overlay Cachy repos onto Arch", then list the extra packages the user still needs.

## Server / headless

If the user wants a headless box:

1. Prefer the experimental Server CLI profile on a current ISO, **or** a desktop/minimal-package install that does not pull a DE.
2. Do not promise a supported minimal ISO.
3. Still use Cachy kernels + ISA repos. `linux-cachyos-server` is a kernel tune (300 Hz, stock EEVDF, preemption **conflict** — verify live), not an install image. See [`kernel.md`](kernel.md).

## MUST / NEVER

- MUST pick Handheld ISO for Deck/Ally/Legion/Claw when the user wants the SteamOS-like session.
- MUST describe existing Arch + `cachyos-repo.sh` as an overlay.
- NEVER invent an offline or official minimal ISO.
- NEVER treat Server CLI profiles as mature just because they appear in the installer.
- NEVER commit installer JSON with `user_pass` / `root_pass` / `zfs_passphrase`.
- NEVER emit `server_mode` in new JSON; use `server_profile` and re-read current `server-profiles.toml`. NEVER invent profile names (`db` is not in that TOML).
