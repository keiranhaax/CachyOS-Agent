# Desktop environments and compositors

Read this before editing DE/WM config, installing "the Arch Hyprland stack", or copying files out of `/etc/skel`.

## `/etc/skel` is for new users only

Cachy DE packages seed `/etc/skel`. That copy happens **once**, when the user is created.

**NEVER "refresh" an existing user by rsyncing `/etc/skel` over `~`.** You will clobber their config. If you need stock files, copy **specific** paths into `~/.config/` after a backup, and say so.

Existing-user customization lives in `~/.config/` and `~/.local/`.

## `cachyos-*-settings` vs stock wikis

Cachy ships settings packages per desktop (`cachyos-kde-settings`, GNOME/XFCE/… equivalents, plus compositor stacks). They **conflict with following stock Arch / upstream DE wikis as the procedure**.

**ALWAYS:**

1. `pacman -Qs cachyos | grep settings` and see what is installed.
2. Read the files that package actually owns (`pacman -Ql <pkg>`).
3. Override in the user config or in `/etc` drop-ins, not by editing packaged files under `/usr/share` or `/usr/lib`.

**NEVER** uninstall `cachyos-*-settings` just so the Arch Wiki recipe "applies cleanly".

## Hyprland on CachyOS is not stock Hyprland

Current Cachy Hyprland is **Noctalia + UWSM**, not a stock `hyprland` + waybar + wofi tree from the Hyprland wiki.

Package: `cachyos-hypr-noctalia` (provides `cachyos-desktop-settings`; depends on `hyprland`, `noctalia`, `uwsm`). It **conflicts** with other `cachyos-desktop-settings` providers such as `cachyos-kde-settings`. Verify live: `pacman -Qs noctalia` / `pacman -Qs hypr`.

```bash
sudo pacman -S cachyos-hypr-noctalia
# log in to the Hyprland (UWSM) session
```

The **live desktop ISO** is KDE. Do not treat `noctalia-greeter` as the ISO display manager.

On a **Hyprland** install only, a greeter is optional: `noctalia-greeter` **or** SDDM. One display manager only. Leave the greeter the installer already enabled unless the user asked to change it.

**NEVER** run `systemctl disable display-manager` or `systemctl enable greetd` as a general step.

User files (existing users; skel does not overwrite these):

| Path | Purpose |
| --- | --- |
| `~/.config/hypr/config/monitors.lua` | Outputs. `hyprctl monitors` for names. |
| `~/.config/hypr/config/variables.lua` | `PRIMARY_MONITOR`, workspace counts (do not exceed 10). |
| `~/.config/hypr/config/inputs.lua` | Keyboard, mouse, touchpad. |
| `~/.config/hypr/config/workspaces.lua` | Workspace assignment / rules. |
| `~/.config/hypr/config/binds.lua` | Keybinds. |
| `~/.config/hypr/config/windowrules.lua` | Window rules. Fetch current syntax from https://wiki.hypr.land/ — it changes. |
| `~/.config/uwsm/env` | `export KEY=VAL` for cursor/Qt/toolkit. Prefer this over `environment.lua`. |
| `~/.config/noctalia/config.toml` | Packaged Noctalia defaults; Super+Z opens the settings UI. |

```bash
hyprctl reload
hyprctl configerrors
hyprctl monitors
```

Skel updates after a `cachyos-hypr-noctalia` upgrade do **not** land in `~`. Merge with `meld /etc/skel/.config/hypr ~/.config/hypr` if the user asked to pick up new dots. Do not blindly overwrite `monitors.lua`.

ALWAYS follow the installed Noctalia / UWSM / Cachy session files.
ALWAYS check what the session actually launches (`echo $XDG_CURRENT_DESKTOP`, `systemctl --user status`).
**`cachyos-hyprland-settings` is archived.** NEVER install it. NEVER revive it as the way to "get Cachy Hyprland back".

If the user wants stock upstream Hyprland, say so, snapshot first, and do not pretend the Cachy session will keep working.

## Other desktops

The live ISO session is KDE. The installer offers 17+ desktops. Each installed DE should be paired with its `cachyos-*-settings` package from the Cachy repos, not with a random AUR dotfiles repo.

Wayland vs X11, login manager (including plasma-login-manager on recent ISOs), and portal stacks are whatever the Cachy profile installed. Check before "fixing" them from memory.

## MUST / NEVER

- MUST treat `/etc/skel` as new-user seed only.
- MUST inspect `cachyos-*-settings` ownership before applying a stock DE wiki.
- MUST treat Hyprland as Noctalia+UWSM on current Cachy.
- NEVER install archived `cachyos-hyprland-settings`.
- NEVER overwrite an existing home with `/etc/skel`.
- NEVER `systemctl disable display-manager` / `enable greetd` as a general Hyprland setup step.
