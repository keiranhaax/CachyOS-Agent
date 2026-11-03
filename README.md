# CachyOS Agent

[![CI](https://github.com/keiranhaax/CachyOS-Agent/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/keiranhaax/CachyOS-Agent/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/keiranhaax/CachyOS-Agent?display_name=tag&sort=semver)](https://github.com/keiranhaax/CachyOS-Agent/releases)
[![License](https://img.shields.io/github/license/keiranhaax/CachyOS-Agent)](LICENSE)

> CachyOS-aware skills and a harness-neutral runtime for AI coding agents, in one signed pacman package.

CachyOS Agent has two parts. The first is the CachyOS skill: reviewed, operational guidance that keeps coding agents from giving vanilla Arch advice on a CachyOS machine. The second is `cachyos-agent`, a runtime for the agents themselves, modeled on [Omarchy's](https://github.com/omacom/omarchy/tree/quattro) agent experience and rebuilt for CachyOS and KDE Plasma. It launches your default coding agent from a shortcut, a desktop entry or a prompt. It shows the usage limits of your agents and subscriptions in a Plasma panel widget, switches between several subscription accounts, hands a crashed program to an agent to diagnose, syncs the Plasma color scheme into the agents' themes, and runs local models through Ollama. It favors no harness. It is Bash, with Python for the usage collectors and the account registry, and every part of it is opt-in. It complements the [official CachyOS wiki](https://wiki.cachyos.org/) but is an independent, unofficial project.

## Quick start

### Recommended: install the signed pacman package

Reviewed tags publish an architecture-independent `cachyos-agent` package and a signed pacman repository. Import and locally sign the maintainer key before enabling the repository.

**Signing key fingerprint:** `8A55 9E3B B6EB 0640 1622 73BC C1D6 43CE B30C 6C59`. Verify it out of band and do not trust a key with a different fingerprint. Releases through `v0.1.1` are unsigned and cannot be installed through this repository.

```bash
curl -fsSLO \
  https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/repo/cachyos-agent-signing-key.asc

gpg --show-keys cachyos-agent-signing-key.asc
sudo pacman-key --add cachyos-agent-signing-key.asc
sudo pacman-key --lsign-key 8A559E3BB6EB0640162273BCC1D643CEB30C6C59

curl -fsSLo cachyos-agent.conf \
  https://raw.githubusercontent.com/keiranhaax/CachyOS-Agent/main/packaging/pacman/cachyos-agent.conf

sudo install -Dm644 cachyos-agent.conf \
  /etc/pacman.d/cachyos-agent.conf

grep -Fxq 'Include = /etc/pacman.d/cachyos-agent.conf' /etc/pacman.conf || \
  printf '\nInclude = /etc/pacman.d/cachyos-agent.conf\n' | sudo tee -a /etc/pacman.conf

sudo pacman -Syu cachyos-agent
cachyos-agent skills provision
```

Inspect `/etc/pacman.conf` before changing it and include the repository fragment only once. Package installation updates the canonical files under `/usr/share/cachyos-agent/`; it does **not** modify user home directories and it enables nothing. Each intended user must run `cachyos-agent skills provision` without `sudo`.

Then choose your coding agent. Nothing is chosen for you:

```bash
cachyos-agent default claude
```

This installs Claude Code if it is missing, makes it your default agent, and **starts it at once, unattended** (see [Using the agents](#using-the-agents)). `cachyos-agent default --help` lists the other agents. Every other part of the runtime is off until you turn it on, and the sections below name each switch.

See [`packaging/README.md`](packaging/README.md) for the repository trust boundary, signing details, and local-build procedure. To run from a Git checkout instead, see [Install from a Git checkout](#install-from-a-git-checkout).

### Upgrade from `cachyos-agent-system`

`cachyos-agent` replaces `cachyos-agent-system` (0.1.x), so `pacman -Syu` removes the old package and installs the new one in one transaction. Skill links the old package's provisioner created point into `/usr/share/cachyos-agent-system`, which pacman removes. The package therefore ships two compatibility names: `/usr/share/cachyos-agent-system`, a symlink to `/usr/share/cachyos-agent`, and `/usr/bin/cachyos-provision-agent-skills`, which runs the provisioner. Existing links keep working through the symlink. Each user should still run `cachyos-agent skills provision` once to move them to the new path, because a later release drops the symlink, and again to link the new `diagnose-crash` skill.

Check a link with `readlink ~/.claude/skills/cachyos`: a target under `cachyos-agent-system` has not been moved yet.

## Using the agents

### The default agent

```bash
cachyos-agent default            # print the default agent, or nothing when none is chosen
cachyos-agent default codex      # install it if missing, make it the default, launch it
cachyos-agent install opencode   # install an agent without choosing it
```

The choice is one line in `~/.config/cachyos-agent/default-agent`. The environment variable `CACHYOS_AGENT_DEFAULT` overrides it. Repository packages are installed with `sudo pacman -S --needed`, AUR packages with `paru -S --needed`, where you read the PKGBUILD that `paru` shows before it builds, and an agent with no package gets its vendor's documented command printed, never run. Neither uses `--noconfirm`, and both run in the terminal you are watching.

### Launch and prompt

```bash
cachyos-agent launch                          # the default agent, in a new terminal window
cachyos-agent launch --inline                 # in this terminal
cachyos-agent launch --agent codex            # another agent, once
cachyos-agent prompt "Review this project"    # the default agent, with a first message
cachyos-agent prompt -- "-v is not a flag"    # -- ends the options
```

The window comes from `$TERMINAL`, then konsole, alacritty, kitty, foot, ghostty and xterm, in that order. A launch from `$HOME` starts in `~/Work` when that directory exists, because agents refuse to remember trust for the home directory. DeepSeek Harness and Freebuff take no starting prompt: they open with the prompt on the clipboard (`wl-copy`, or Klipper through `qdbus6`), or printed in their window when neither is available.

### Launched agents do not stop to ask

`launch`, `prompt`, `default <agent>`, the desktop entry, the shortcut, the panel widget's Launch button and the crash notification's Diagnose button all start the agent **unattended, in its own don't-stop-to-ask mode**. It will edit files and run commands without asking you first. The first line in the new window says so and names the flags it used, for example `cachyos-agent: starting Claude Code with --permission-mode auto, which does not stop to ask before acting`. With `--inline` the line goes to stderr.

| Id | Agent | Installed with | Starts with |
|---|---|---|---|
| `pi` | Pi | vendor npm command | none |
| `omp` | Oh My Pi | AUR `oh-my-pi` | `--auto-approve` |
| `opencode` | OpenCode | pacman `opencode` | `--auto` |
| `ori` | Ori | vendor script | none (`ori code`) |
| `claude` | Claude Code | pacman `claude-code` | `--permission-mode auto` |
| `codex` | Codex | pacman `openai-codex` | `--approve-for-me` |
| `grok` | Grok | AUR `grok-build` | `--permission-mode bypassPermissions` |
| `agy` | Antigravity | AUR `antigravity-cli` | `--dangerously-skip-permissions` |
| `hermes` | Hermes | pacman `hermes-agent` | `--yolo` |
| `copilot` | GitHub Copilot | pacman `github-copilot-cli` | `--allow-all` |
| `crush` | Crush | AUR `crush` | `--yolo`; with a prompt it runs `crush run`, which never asks |
| `cursor-agent` | Cursor CLI | AUR `cursor-cli` | `--yolo --trust` |
| `muse` | Muse Code | vendor script | `--approval-mode never` |
| `kimi` | Kimi | vendor npm command | `--yolo`; with a prompt it runs `--prompt`, which is non-interactive print mode |
| `qwen` | Qwen Code | pacman `qwen-code` | `--yolo` |
| `dsh` | DeepSeek Harness | vendor npm command | `DSH_PERMISSION_MODE=danger-full-access` |
| `mcode` | MiniMax Code | vendor npm command | none; it asks for permissions as usual |
| `kiro-cli` | Kiro CLI | AUR `kiro-cli` | `--trust-all-tools` |
| `freebuff` | Freebuff | vendor npm command | none |
| `kilo` | Kilo | AUR `kilo-bin` | `--auto` |
| `devin` | Devin CLI | vendor script | `--permission-mode dangerous` and `--respect-workspace-trust false` |
| `amp` | Amp | AUR `ampcode` | `--dangerously-allow-all` |
| `commandcode` | Command Code | AUR `command-code` | `--yolo` |

The flags follow each vendor's documentation as of November 2026, and Omarchy's where the author had no copy of the agent to check. A vendor can rename one: if an agent exits at once with a usage error, compare `<agent> --help` with this table. A vendor npm command is printed with `--prefix ~/.local`, so it installs into your home directory and needs the `nodejs` and `npm` packages. A shell-script installer is never piped into a shell: read it, then run it yourself.

### A key that opens your agent

```bash
cachyos-agent shortcut set             # Meta+Ctrl+Shift+A
cachyos-agent shortcut set Meta+Alt+A  # or your own combination
cachyos-agent shortcut show
cachyos-agent shortcut unset
```

This writes a Plasma global shortcut for `cachyos-agent.desktop` into `~/.config/kglobalshortcutsrc` with `kwriteconfig6` (package `kconfig`). Plasma reads shortcuts when you log in, so a change applies after your next login. The shortcut runs `cachyos-agent launch --pick`: with a default agent it launches it, and without one it shows a notification that lists the agents and how to choose. A combination needs a modifier (Meta, Ctrl, Alt or Shift) so that it never takes a plain key away from your applications.

### The desktop entry

The package installs `cachyos-agent.desktop`, "CachyOS Agent" under Development in the application launcher. It runs `cachyos-agent launch --pick`, the same as the shortcut. The launcher and Plasma start it with their own `PATH`, so `cachyos-agent` must be somewhere on it (the package puts it in `/usr/bin`).

### Short names in your shell

Add one line to your shell configuration. Neither file is sourced for you.

```bash
# ~/.bashrc
source /usr/share/cachyos-agent/shell/cachyos-agent.bash
```

```fish
# ~/.config/fish/config.fish
source /usr/share/cachyos-agent/shell/cachyos-agent.fish
```

| Name | Runs | Arguments |
|---|---|---|
| `a` | `cachyos-agent launch --inline`: the default agent in this terminal | the options of `launch`, such as `--local`; for a prompt use `cachyos-agent prompt --inline` |
| `c` | `opencode --auto` | passed to OpenCode |
| `cx` | `cachyos-agent account exec claude --permission-mode auto`: Claude Code as the selected account | passed to Claude Code |
| `cy` | `cachyos-agent account exec codex --approve-for-me`: Codex as the selected account | passed to Codex |

Each runs unattended, in the current terminal. `a`, `cx` and `cy` follow [`cachyos-agent account use`](#several-subscriptions); `c` and a plain `claude` or `codex` do not.

## The agents panel

Every agent in use has a usage record: its plan, its limit windows with the time until they reset, a prepaid balance where it has one, and the tokens and prompts counted from its own session files. A collector writes each record, and there are 23: Antigravity, Claude Code, Codex, GitHub Copilot, Cursor, DeepSeek, Devin, Fireworks, Grok, Grok Bot, Hermes, Kimchi, Kimi, local models, MiniMax, Muse, Ollama Cloud, OpenCode, OpenRouter, Qwen Code, Synthetic, Mistral Vibe and Z.ai. What a record holds depends on the service. Sessions you drive through pi, Oh My Pi or OpenCode are counted under whoever bills them, not under the harness. The collectors were ported from Omarchy and follow its endpoints and credential layouts.

```bash
cachyos-agent usage                  # the report, from the records already written
cachyos-agent usage update           # collect fresh records now (--force, --limits-only, --except <agent>)
cachyos-agent usage schedule on      # a systemd user timer: refresh every 15 minutes
cachyos-agent usage -- claude codex  # only these agents
cachyos-agent usage --json claude    # the raw records, as a JSON array
```

A report looks like this (an example):

```text
Claude Code  Max
  5-hour   42%  resets in 3h 0m
  Weekly   95%  resets in 2d 22h
  Tokens   today 2.4M, this week 28M
  Prompts  today 12, all time 900

OpenRouter  Prepaid
  Balance  $8.50 left of $20.00 (spent $11.50)
```

`cachyos-agent usage claude` does not filter the report: a first word that names a collector runs that collector and prints a fresh raw record. Put `--` or `--json` before the agent names to filter.

Records live in `~/.local/state/cachyos-agent/usage/<agent>.json`. A record that nothing has refreshed for an hour says "updated … ago" next to the agent's name, and a limit whose reset time has passed reads 0%. A collector reads the credentials the agent's CLI left, or an API key, and does not edit an agent's files. The one exception is Kimi: it renews its expiring sign-in token the way the Kimi CLI does, under the CLI's lock.

**The timer does not see your shell's environment.** It runs in the systemd user manager, so a key exported only in `config.fish` or `.bashrc` is missing there, and the timer would replace a record written from your shell with one that says the agent is not in use. Keep keys in `~/.config/environment.d/*.conf` (`NAME=value` lines, read at login) or, for the collectors that read one, in `~/.config/cachyos-agent/<agent>.json` (`deepseek`, `copilot`, `fireworks`, `local`, `ollama`, `openrouter` and `zai`). The collectors for DeepSeek, Fireworks, MiniMax, Ollama Cloud, OpenRouter, Synthetic, Z.ai and Kimchi read variables such as `DEEPSEEK_API_KEY` and `OPENROUTER_API_KEY`, and most also find the key you gave pi, Oh My Pi or OpenCode.

### The Plasma widget

The package installs the widget "CachyOS Agents". To put it in a panel, right-click the panel, choose Add Widgets, and search for it; the same works on the desktop. It lists each agent with its plan, a meter for every limit window with the time until it resets, the prepaid balance, and the tokens used, with the active account marked where several are registered. The buttons are Launch agent (`cachyos-agent launch`) and Refresh (`cachyos-agent usage update --force`). The tooltip names each agent's fullest limit, and the widget asks the shell for attention when a limit reaches 90% or a balance is down to 10%.

The widget only displays. It reads `cachyos-agent usage --json` when it opens and every 900 seconds (change that under Configure, from 30 to 3600), and the records change only when the timer or Refresh runs, so turn the timer on. It needs `plasma-desktop`, which brings `plasma5support` and `kcmutils`. Not ported from Omarchy's panel: sign-in links, switching accounts from the panel, the add-subscription flow, local model status and the starter prompts.

## Several subscriptions

If you pay for more than one Claude, Codex or Grok plan, `cachyos-agent account` keeps them all signed in and lets you move between them.

```bash
cachyos-agent account add claude Work   # sign in to another Claude subscription
cachyos-agent account list              # every account, with its latest limits
cachyos-agent account use work          # new sessions start as Work
cachyos-agent account use main          # and back
cachyos-agent account mode auto 90      # switch by itself at 90%
```

The CLI must already be installed (`cachyos-agent install claude`). The first account of a provider signs in through your normal browser, where the CLI always looks. Every later one signs in through a private window of your default browser (Chromium-based browsers get `--incognito`, Edge `--inprivate`, Firefox-based ones `--private-window`, and any other browser just prints the link), so the account your browser is already signed in to is not picked up by mistake. Close any private window you already had open first. **Never log out of the CLI to add an account:** logging out revokes the saved sign-in, and that account would have to be added again. The login you already had in `~/.claude`, `~/.codex` or `~/.grok` is the Main account and stays where it is. If no default agent is chosen yet, the first sign-in makes that provider the default.

`account use` takes the provider first when your default agent is not one of the three (`cachyos-agent account use codex side`), and `next` cycles through the accounts. Others: `account rename`, `account remove` (which forgets an added account and deletes its home, and asks first when run in a terminal), and `account add --reauth <account>` to sign a lapsed account in again.

- **Which sessions follow the choice.** Only sessions started with `cachyos-agent launch`, or with `cachyos-agent account exec <provider>` (which is what `cx` and `cy` run), start as the selected account. A plain `claude`, `codex` or `grok` always uses `~/.claude`, `~/.codex` or `~/.grok`. Sessions already running keep their account.
- **An explicit home wins.** `CLAUDE_CONFIG_DIR`, `CODEX_HOME` or `GROK_HOME`, when you set one, beats the selection.
- **Near a limit.** By default you get a notification when the active account passes 95% of a limit; its action switches new sessions to the account with the most headroom, and the body gives the `account use` command for when the notification is gone. `account mode auto` switches by itself instead, and a number sets the threshold, from 50 to 100.
- **Where it is kept.** The registry is `~/.local/state/cachyos-agent/accounts/<provider>.json` and each added account has a home under `accounts/<provider>/<id>/`. An added account's home holds only its credentials and links everything else back to the Main account's home, so conversation history, settings and skills stay one set across accounts.

Not ported from Omarchy: `account copy` and `account transfer` (moving logins to another machine), and the account controls in the panel.

## Crash diagnosis

When one of your programs crashes, `cachyos-agent` can offer to have your default agent work out why. It follows `systemd-coredump` through the journal (`coredumpctl list` shows what it records) and needs `libnotify` 0.8.8 or newer.

```bash
cachyos-agent crash capture on       # run the watcher for every login, and now
cachyos-agent crash capture status
cachyos-agent crash capture off
cachyos-agent crash 1516893          # diagnose a crash by hand: any PID from coredumpctl list
```

With the watcher on, a crash raises a "Process crashed" notification with a Diagnose button. Choosing it opens your default agent in a new terminal, unattended like any other launch, with the [`diagnose-crash`](agents/skills/diagnose-crash/SKILL.md) skill. The skill walks the agent through establishing the facts from the core dump and deciding whether the crash is worth reporting upstream. The names and paths in the prompt come from the crashed program, so they are cut to one line and the agent is told they are data. Nothing is announced until a default agent is chosen.

Silence one program at a time, which is what the diagnosis offers at its end:

```bash
cachyos-agent crash mute plasmashell        # stop the notifications for that program
cachyos-agent crash mute plasmashell off    # bring them back
cachyos-agent crash mute                    # list what is muted
```

A path such as `/usr/bin/plasmashell` works as well as a name. The program still crashes; only the notification goes. Only your own programs are announced, one notification per program in any 60 seconds, and never the runtime's own commands. Two variables tune the watcher, which you set in a drop-in of `cachyos-agent-crash-watch.service` (`systemctl --user edit`): `CACHYOS_AGENT_CRASH_IGNORE`, an extended regular expression of program names never announced, and `CACHYOS_AGENT_CRASH_DEDUPE_SECONDS`. A crash of `plasmashell` takes the notification server down with it, so the watcher waits up to 20 seconds for the restarted shell before it gives up on a notification.

## Theme sync

```bash
cachyos-agent theme sync                      # publish the Plasma color scheme to your agents
cachyos-agent theme sync --activate           # and make it their theme
cachyos-agent theme sync --only claude,pi
cachyos-agent theme follow on                 # repeat the sync whenever the color scheme changes
```

`theme sync` reads the active Plasma color scheme from `~/.config/kdeglobals` (or the scheme file it names, or Breeze Dark) and writes a theme called `cachyos` for four agents:

| Agent | File | `--activate` |
|---|---|---|
| Hermes | `skins/cachyos.yaml` in `$HERMES_HOME` (`~/.hermes`) and every profile | runs `hermes skin use cachyos`; Hermes must have run once |
| Claude Code | `~/.claude/themes/cachyos.json` (or `$CLAUDE_CONFIG_DIR`) | sets `theme` to `custom:cachyos` in `settings.json` |
| Pi | `~/.pi/agent/themes/cachyos.json` | sets `theme` in `settings.json` |
| OpenCode | `~/.config/opencode/themes/cachyos.json` | sets `theme` in `tui.json`; with a `tui.jsonc` it leaves the choice to you (`/theme`) |

Without `--activate` only an agent whose directory already exists gets the file, and no agent is switched, so a theme you chose yourself stays. An unchanged file is not rewritten, and one agent failing does not stop the rest. Claude Code and Pi reload a changed theme file while they run (a `themes/` folder created after Claude Code started needs one restart); OpenCode needs a restart or `/theme`.

`theme follow on` enables a user path unit that watches `kdeglobals` and runs `theme sync` (without `--activate`) when it changes. It does not sync by itself when you turn it on: run `cachyos-agent theme sync` once. `theme follow off` stops it.

## Local models

Run an open model on your own machine for your coding agents, through [Ollama](https://ollama.com/). What you send to that model stays on the machine.

```bash
cachyos-agent local list          # the recipes, and whether each fits this machine
cachyos-agent local use best      # install Ollama if needed, download the best fit
cachyos-agent launch --local      # open an agent on it
```

`local list` shows the eight recipes in `data/local-models.tsv`, strongest first, with each one's download size and context. A recipe fits `gpu` when the model stays in GPU memory, `cpu` when it only runs with part or all of it in RAM, and `no` when it does not run at all. The memory thresholds are estimates. `local use best` takes the first recipe that fits in GPU memory, else the first that fits in RAM; `local use <id>` takes a named one.

`local use` runs `sudo` in your terminal and asks first. It offers `sudo pacman -S --needed ollama-cuda` (NVIDIA), `ollama-rocm` (AMD) or `ollama` (CPU only); starts `ollama.service` with `sudo systemctl enable --now` when the server does not answer; downloads the model; and creates it under the recipe's id with a 32K or 64K context, because Ollama's own default is 4K below 24 GiB of VRAM, too small for an agent. Models live in `/var/lib/ollama`, so expect tens of GB on the system disk, and snapper snapshots keep the files of a model you later delete. When the download plus 10 GB would not fit, it asks before it starts.

`cachyos-agent launch --local` opens your default agent on the model when that agent is pi or OpenCode, and otherwise whichever of the two is installed (pi first). It points the agent at the model for that run only and does not edit the agent's own configuration. `--local-model <name>` picks another model.

The server is at `http://127.0.0.1:11434/v1`. Any OpenAI-compatible client can use it: the model name is the recipe id, and any API key text is accepted. `local status` shows the service, the loaded models and the active model. `local stop` stops the service and frees the memory the models hold, `local start` starts it, and `local remove <id>` deletes a model and its download.

## The CachyOS skill

The runtime is the part you run. The skill is the part your agents read.

Vanilla Arch advice is actively wrong in several CachyOS-specific areas, including ISA repositories, kernel modules, scheduler integration, Limine/snapper, `chwd`, shipped settings, desktop packages, and handhelds. The `cachyos` skill helps agents inspect the live system, choose the CachyOS-native path, plan risky work, and verify the result. The `diagnose-crash` skill is what a crash notification hands to your agent. Agents are first-class here: the project never favors a particular harness, and its skills are guidance rather than unattended authority. The one place the runtime acts without asking is the launcher, and it says so (see [Launched agents do not stop to ask](#launched-agents-do-not-stop-to-ask)).

### What provisioning changes

`cachyos-agent skills provision` links each directory under `agents/skills/` (`cachyos` and `diagnose-crash`) into every supported agent harness:

| Harness | Path |
|---|---|
| Generic agents | `~/.agents/skills/<name>` |
| Claude | `~/.claude/skills/<name>` |
| Codex | `~/.codex/skills/<name>` |
| Pi | `~/.pi/agent/skills/<name>` |
| Gemini | `~/.gemini/config/skills/<name>` |
| Hermes Agent | `${HERMES_HOME:-$HOME/.hermes}/skills/<name>` |

Provisioning is idempotent. Without `--force`, existing regular files and directories are left untouched. With `--force`, an existing skill directory is moved to a timestamped sibling backup before its link is created. The provisioner never recursively deletes a skill and refuses sources without `SKILL.md`.

Links from a Git installation track that checkout. Moving the checkout breaks them until the provisioner is run again from the new location. New skill names are also linked only after the provisioner is rerun.

### Hermes Agent profiles

Hermes scopes each profile through `HERMES_HOME`; the default profile lives at `~/.hermes`. Provision a named profile by re-running with the variable set:

```bash
# Default Hermes profile
cachyos-agent skills provision

# Named Hermes profile
HERMES_HOME="$HOME/.hermes/profiles/coder" \
  cachyos-agent skills provision
```

Verify discovery with `hermes skills list | grep -F cachyos`. In an already-running chat, run `/reload-skills` to re-scan for the new skill without discarding the session. Hermes users who already scan a shared directory through `skills.external_dirs` (for example `~/.agents/skills`) do not need the direct link; both entries resolve to the same `SKILL.md`, which Hermes deduplicates, so having both is harmless but redundant.

Because the link resolves outside `$HERMES_HOME/skills`, Hermes logs a harmless "outside the trusted skills directory" warning when loading the skill. Adding the packaged path (or the linked shared directory) to `skills.external_dirs` marks it trusted and silences the warning.

Hermes's agent-managed skill editing cannot modify the linked skill when it resolves to the root-owned packaged files; that is intentional, as the package remains the source of truth.

### Topic guides

| Guide | Purpose |
|---|---|
| [`SKILL.md`](agents/skills/cachyos/SKILL.md) | Required safety path, command discovery and decision framework for CachyOS work. |
| [`kernel.md`](agents/skills/cachyos/kernel.md) | `linux-cachyos*` variants, Kernel Manager, and matching modules. |
| [`repos.md`](agents/skills/cachyos/repos.md) | ISA repositories, ordering, mirrorlists, and migrations. |
| [`performance.md`](agents/skills/cachyos/performance.md) | sched-ext, Ananicy, GameMode, ZRAM, and I/O tuning. |
| [`hardware.md`](agents/skills/cachyos/hardware.md) | `chwd` profiles, GPU migrations, and NVIDIA modules. |
| [`boot.md`](agents/skills/cachyos/boot.md) | Limine, snapper snapshots, recovery, and `cachy-chroot`. |
| [`desktop.md`](agents/skills/cachyos/desktop.md) | Packaged desktop defaults, `/etc/skel`, Noctalia, and UWSM. |
| [`install.md`](agents/skills/cachyos/install.md) | ISO choices, installation, and Arch repository overlays. |
| [`packaging.md`](agents/skills/cachyos/packaging.md) | CachyOS PKGBUILDs, repository choice, march, LTO, and PGO. |
| [`handheld.md`](agents/skills/cachyos/handheld.md) | Handheld Edition, deckify kernels, and `scx_lavd`. |
| [`agent.md`](agents/skills/cachyos/agent.md) | The coding agents themselves: the default agent, usage, accounts, crash notifications, themes, local models, and what an agent must not do unasked. |
| [`diagnose-crash`](agents/skills/diagnose-crash/SKILL.md) | A separate skill: diagnose a crash from its core dump. [`reporting.md`](agents/skills/diagnose-crash/reporting.md) decides whether it is CachyOS's bug. |

### Safety model

1. Inspect the live system before changing it.
2. Treat CachyOS as different from vanilla Arch.
3. Plan destructive changes before applying them.
4. Take a snapper snapshot before destructive work.
5. Prefer CachyOS tools and installed package data.
6. Verify after every change.
7. Never edit shipped files under `/usr/lib`.
8. Never pull and execute arbitrary Git changes from a root pacman hook.

Prefer rollback through Limine snapshots or snapper over heroic undo. When published sources disagree, verify against the running system with tools such as `pacman -Si`, `kerver`, and `chwd`.

## Command reference

`cachyos-agent <group> <command>` runs the executable `cachyos-agent-<group>-<command>`. `cachyos-agent <group> --help` shows a group, `cachyos-agent <command> --help` shows one command without running it, and `cachyos-agent commands --json` is the machine-readable list. This table is the output of `cachyos-agent commands`, and `test/cases/85-docs.sh` fails when it drifts.

| Command | What it does |
|---|---|
| `cachyos-agent account add` | Sign in to a Claude, Codex, or Grok subscription |
| `cachyos-agent account list` | List Claude, Codex, and Grok subscription accounts and their limits |
| `cachyos-agent account mode` | Switch Claude, Codex, or Grok accounts automatically near a limit, or only notify |
| `cachyos-agent account remove` | Forget an added Claude, Codex, or Grok account |
| `cachyos-agent account rename` | Rename a Claude, Codex, or Grok subscription account |
| `cachyos-agent account use` | Choose which Claude, Codex, or Grok account new sessions use |
| `cachyos-agent crash` | Diagnose a crashed process with the default coding agent |
| `cachyos-agent crash capture` | Turn the crash watcher on or off, or show whether it runs |
| `cachyos-agent crash mute` | Silence crash notifications for one program, or list what is silenced |
| `cachyos-agent default` | Show, or choose and launch, the default coding agent |
| `cachyos-agent install` | Install an agent CLI with pacman or paru |
| `cachyos-agent launch` | Launch the default coding agent in a terminal |
| `cachyos-agent local` | Run open models on this machine for your agents |
| `cachyos-agent prompt` | Launch the default coding agent with a prompt |
| `cachyos-agent shortcut` | Bind, show or remove the Plasma global shortcut that opens the agent |
| `cachyos-agent skills check-upstreams` | Compare reviewed CachyOS upstream commits with the current branch heads |
| `cachyos-agent skills provision` | Link the CachyOS skill into every agent harness |
| `cachyos-agent skills update` | Fast-forward a clean Git checkout and refresh the harness links |
| `cachyos-agent skills validate` | Validate the skill tree: frontmatter, links, indexes, scripts |
| `cachyos-agent theme follow` | Re-sync the agent themes whenever the Plasma color scheme changes |
| `cachyos-agent theme sync` | Sync the Plasma color scheme into Hermes, Claude Code, Pi and OpenCode |
| `cachyos-agent usage` | Show agent limits, balances and token usage; to filter, put -- or --json before the agent names, because a bare name runs that agent's collector |
| `cachyos-agent usage schedule` | Refresh the usage records every 15 minutes with a systemd user timer |
| `cachyos-agent usage update` | Regenerate the agent usage records |

`cachyos-agent commands --all` also lists the plumbing commands: `account exec` (run a CLI as the selected account), `account home` and `account state` (the account registry), `crash watch` (what the crash service runs), `theme palette` (the palette the themes are rendered from), and the 23 `usage <agent>` collectors. `cachyos-agent version` prints the version.

## Install from a Git checkout

Keep the checkout in a stable location so its provisioned links remain valid.

```bash
git clone https://github.com/keiranhaax/CachyOS-Agent.git \
  ~/.local/share/cachyos-agent

cd ~/.local/share/cachyos-agent
./bin/cachyos-agent-skills-provision

# Put the dispatcher on your PATH. The other commands are found beside it.
mkdir -p ~/.local/bin
ln -s ~/.local/share/cachyos-agent/bin/cachyos-agent ~/.local/bin/cachyos-agent
```

Run `./bin/cachyos-agent-skills-provision --help` for source and replacement options. The commands find the checkout through the real path of the script they run, so a link to `bin/cachyos-agent` is enough. Do not run a checkout beside the installed package unless you put the checkout first with `PATH=$PWD/bin:$PATH`, or each command will find the packaged copies of the others.

The pieces the package installs for you come from the checkout like this (run these from the checkout directory):

| Piece | From a checkout |
|---|---|
| Units (`usage schedule on`, `crash capture on`, `theme follow on`) | Each command writes marked copies of the units from `systemd/user/` into `~/.config/systemd/user/`, pointing at the checkout, and `off` removes them again. A unit you wrote yourself is never overwritten. A checkout path with a space or other unusual character is refused by `theme follow`, and a quote or backslash is refused by the others, so keep the checkout at a plain path such as `~/.local/share/cachyos-agent`. |
| Desktop entry and shortcut | `install -Dm644 desktop/cachyos-agent.desktop ~/.local/share/applications/cachyos-agent.desktop`, then `cachyos-agent shortcut set`. The shortcut command prints this line when it cannot find the entry. |
| Panel widget | `kpackagetool6 --type Plasma/Applet --install plasmoid/org.cachyos.agent` (`--upgrade` after an update). The widget and the desktop entry start `cachyos-agent` with the session's `PATH`, so link it into a directory on that `PATH`. |
| Shell names | `source ~/.local/share/cachyos-agent/shell/cachyos-agent.bash` (or `.fish`) |

A checkout from before 0.2.0 has `bin/cachyos-provision-agent-skills`, which no longer exists: only the package keeps that name. Running that checkout's own `skills update` fast-forwards it and then stops with `cachyos-provision-agent-skills is not installed`, before the upstream check. Run `./bin/cachyos-agent-skills-provision` once by hand; later updates use the new name.

## Updates and freshness

Pacman installations receive reviewed releases through normal `pacman -Syu` transactions. A timer, the crash watcher and the theme follower run the package's files, and an upgrade replaces them in place; a crash watcher that is already running keeps the old files until it restarts (`systemctl --user restart cachyos-agent-crash-watch.service`). Git installations can run `cachyos-agent skills update`, which permits only a clean fast-forward update and refuses dirty or divergent trees.

Run `cachyos-agent skills check-upstreams` after a CachyOS update or before publishing a release. It detects relevant upstream movement for human review; it never treats a changed commit hash as proof that guidance is still correct and never rewrites guidance automatically.

## Validate and develop

Run the release checks natively on CachyOS or Arch with GNU userland:

```bash
./bin/cachyos-agent-skills-validate
./bin/cachyos-agent commands --check
./test/run-tests
shellcheck -x $(grep -lE '^#!/bin/bash' bin/*) lib/*.sh test/run-tests test/lib.sh test/cases/*.sh
PYTHONPYCACHEPREFIX=$(mktemp -d) python3 -m py_compile $(grep -lE '^#!/usr/bin/(env )?python' bin/*) lib/*.py
namcap PKGBUILD
```

`test/run-tests` runs every `test/cases/NN-<feature>.sh` in its own process: the dispatcher and shared helpers (`00`, `01`), the skills (`10`), the launcher (`20`), crash diagnosis (`30`), theme sync (`40`), usage (`50`), accounts (`60`), local models (`70`), the widget (`80`) and the documents (`85`). A case works in a sandbox home, with stubs for every external program, and never needs the network, root, a display or a real agent CLI. A case whose tool is missing (`kconfig`, `fish`, `node`, the Qt 6 and Plasma QML modules) prints `skip` or `UNVERIFIED` and passes. See [`MAINTENANCE.md`](MAINTENANCE.md) for adding a command, the upstream review and the release checklist.

<details>
<summary>Repository layout</summary>

```text
AGENTS.md                         Philosophy, skill index and the command-discovery rule
MAINTENANCE.md                    Layout, adding a command, upstream review, release checklist
THIRD_PARTY_NOTICES.md            Omarchy attribution: every adapted file, and the MIT notice
VERSION upstreams.tsv LICENSE     Version, reviewed sources, and project license
agents/skills/cachyos/            Umbrella skill and CachyOS topic guides, including agent.md
agents/skills/diagnose-crash/     Crash diagnosis skill
bin/                              cachyos-agent and its cachyos-agent-<group>-<command> commands
lib/                              common.sh, per-feature helpers, collectors.py
data/                             Theme templates, local model recipes, Pi extension
shell/                            a, c, cx and cy for bash and fish
desktop/                          cachyos-agent.desktop
systemd/user/                     Units for usage, crash capture and theme follow
plasmoid/org.cachyos.agent/       The panel widget
test/run-tests test/lib.sh        Test runner and helpers
test/cases/                       One case per feature, plus the widget QML harness in test/plasmoid/
PKGBUILD .SRCINFO                 Arch/CachyOS package recipe and metadata
cachyos-agent.install             Messages shown when the package is installed or upgraded
packaging/                        Pacman repository configuration and release notes
.github/workflows/ci.yml          Validation on every push and pull request
.github/workflows/release.yml     Signed package and repository publication
```

</details>

## Acknowledgements

The runtime is adapted from [Omarchy's agent experience](https://github.com/omacom/omarchy/tree/quattro): its launcher and default agent, crash diagnosis, usage collectors and panel, subscription accounts, theme sync and local models. The skill was already modeled on Omarchy's agent-friendly architecture, particularly its `AGENTS.md` conventions, skill organization, and multi-agent provisioning approach. Omarchy was created by [David Heinemeier Hansson](https://github.com/dhh) and is distributed under the MIT License. [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists every adapted file with the Omarchy path it came from and the commit it was taken at, and preserves the complete upstream notice.

CachyOS Agent is an independent project and is not affiliated with or endorsed by Omarchy, Basecamp, or CachyOS.

## License

Original CachyOS Agent code and guidance are licensed under GPL-3.0-only; see [`LICENSE`](LICENSE). Omarchy's separate MIT notice is preserved in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
