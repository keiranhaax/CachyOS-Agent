# Third-party notices

## Omarchy

CachyOS Agent's agent runtime, `cachyos-agent`, is adapted from the agent experience in [Omarchy](https://github.com/omacom/omarchy/tree/quattro): its launcher, default agent, crash diagnosis, usage collectors, subscription accounts, theme sync, local models, and the agents panel. Omarchy was created by David Heinemeier Hansson and is distributed under the MIT License. The CachyOS skill and its provisioning were already modelled on Omarchy's agent-friendly architecture, particularly its `AGENTS.md` conventions, skill organization, and multi-agent provisioning approach.

The code was adapted from Omarchy's `quattro` branch at commit [`8d07724582326e2604db60fd772395b3e5c94777`](https://github.com/omacom/omarchy/commit/8d07724582326e2604db60fd772395b3e5c94777) (2026-11-02). Omarchy is built for Hyprland and Quickshell; this port targets CachyOS with KDE Plasma and changes the code accordingly. The ported files are listed below, each with the Omarchy path it came from, relative to the root of that commit. Every file in the first table has a comment near its top that names its origin and points here. JSON has no comments, and the skills end with their notice in prose, so the files in the second table are listed without that comment.

CachyOS Agent is an independent project and is not affiliated with or endorsed by Omarchy, Basecamp, or CachyOS.

### Files adapted from Omarchy

| File | Omarchy origin |
|---|---|
| `bin/cachyos-agent` | bin/omarchy |
| `bin/cachyos-agent-account-add` | bin/omarchy-agent-account-add |
| `bin/cachyos-agent-account-exec` | bin/omarchy-agent-account-exec |
| `bin/cachyos-agent-account-home` | bin/omarchy-agent-account-home |
| `bin/cachyos-agent-account-list` | bin/omarchy-agent-account-list |
| `bin/cachyos-agent-account-mode` | bin/omarchy-agent-account-mode |
| `bin/cachyos-agent-account-remove` | bin/omarchy-agent-account-remove |
| `bin/cachyos-agent-account-rename` | bin/omarchy-agent-account-rename |
| `bin/cachyos-agent-account-state` | bin/omarchy-agent-account-state |
| `bin/cachyos-agent-account-use` | bin/omarchy-agent-account-use |
| `bin/cachyos-agent-crash` | bin/omarchy-agent-crash |
| `bin/cachyos-agent-crash-capture` | bin/omarchy-toggle-crash-capture |
| `bin/cachyos-agent-crash-mute` | bin/omarchy-crash-mute |
| `bin/cachyos-agent-crash-watch` | bin/omarchy-crash-watch |
| `bin/cachyos-agent-default` | bin/omarchy-default-agent |
| `bin/cachyos-agent-install` | bin/omarchy-default-agent |
| `bin/cachyos-agent-launch` | bin/omarchy-agent |
| `bin/cachyos-agent-local` | bin/omarchy-agent-local |
| `bin/cachyos-agent-prompt` | bin/omarchy-agent-prompt |
| `bin/cachyos-agent-theme-palette` | bin/omarchy-theme-color |
| `bin/cachyos-agent-theme-sync` | bin/omarchy-theme-set-claude, omarchy-theme-set-hermes and omarchy-theme-set-pi |
| `bin/cachyos-agent-usage-agy` | bin/omarchy-agent-usage-agy |
| `bin/cachyos-agent-usage-claude` | bin/omarchy-agent-usage-claude |
| `bin/cachyos-agent-usage-codex` | bin/omarchy-agent-usage-codex |
| `bin/cachyos-agent-usage-copilot` | bin/omarchy-agent-usage-copilot |
| `bin/cachyos-agent-usage-cursor` | bin/omarchy-agent-usage-cursor |
| `bin/cachyos-agent-usage-deepseek` | bin/omarchy-agent-usage-deepseek |
| `bin/cachyos-agent-usage-devin` | bin/omarchy-agent-usage-devin |
| `bin/cachyos-agent-usage-fireworks` | bin/omarchy-agent-usage-fireworks |
| `bin/cachyos-agent-usage-grok` | bin/omarchy-agent-usage-grok |
| `bin/cachyos-agent-usage-grokbot` | bin/omarchy-agent-usage-grokbot |
| `bin/cachyos-agent-usage-hermes` | bin/omarchy-agent-usage-hermes |
| `bin/cachyos-agent-usage-kimchi` | bin/omarchy-agent-usage-kimchi |
| `bin/cachyos-agent-usage-kimi` | bin/omarchy-agent-usage-kimi |
| `bin/cachyos-agent-usage-local` | bin/omarchy-agent-usage-local |
| `bin/cachyos-agent-usage-minimax` | bin/omarchy-agent-usage-minimax |
| `bin/cachyos-agent-usage-muse` | bin/omarchy-agent-usage-muse |
| `bin/cachyos-agent-usage-ollama` | bin/omarchy-agent-usage-ollama |
| `bin/cachyos-agent-usage-opencode` | bin/omarchy-agent-usage-opencode |
| `bin/cachyos-agent-usage-openrouter` | bin/omarchy-agent-usage-openrouter |
| `bin/cachyos-agent-usage-qwen` | bin/omarchy-agent-usage-qwen |
| `bin/cachyos-agent-usage-synthetic` | bin/omarchy-agent-usage-synthetic |
| `bin/cachyos-agent-usage-update` | bin/omarchy-agent-usage-update |
| `bin/cachyos-agent-usage-vibe` | bin/omarchy-agent-usage-vibe |
| `bin/cachyos-agent-usage-zai` | bin/omarchy-agent-usage-zai |
| `data/themed/hermes.yaml.tpl` | default/themed/hermes.yaml.tpl |
| `lib/accounts.sh` | bin/omarchy-agent-account-* |
| `lib/collectors.py` | shell/plugins/agents/collectors.py |
| `lib/common.sh` | bin/omarchy-toggle, omarchy-cmd-present and omarchy-notification-send |
| `lib/crash.sh` | bin/omarchy-crash-watch and omarchy-crash-mute |
| `lib/launcher.sh` | bin/omarchy-default-agent and omarchy-cmd-present |
| `lib/theme.sh` | bin/omarchy-theme-color |
| `plasmoid/org.cachyos.agent/contents/code/records.js` | shell/plugins/agents/Panel.qml and Main.qml |
| `plasmoid/org.cachyos.agent/contents/ui/AgentSection.qml` | shell/plugins/agents/Panel.qml |
| `plasmoid/org.cachyos.agent/contents/ui/FullRepresentation.qml` | shell/plugins/agents/Panel.qml |
| `plasmoid/org.cachyos.agent/contents/ui/LimitList.qml` | shell/plugins/agents/Panel.qml |
| `plasmoid/org.cachyos.agent/contents/ui/main.qml` | shell/plugins/agents/Main.qml and Panel.qml |
| `systemd/user/cachyos-agent-crash-watch.service` | default/systemd/user/omarchy-crash-watch.service |

### Files adapted from Omarchy that carry no header

| File | Omarchy origin |
|---|---|
| `agents/skills/diagnose-crash/SKILL.md` | default/agents/skills/diagnose-crash/SKILL.md |
| `agents/skills/diagnose-crash/reporting.md` | default/agents/skills/diagnose-crash/reporting.md |
| `data/themed/claude.json.tpl` | default/themed/claude.json.tpl |
| `data/themed/pi.json.tpl` | default/themed/pi.json.tpl |

Any other file in the repository is original CachyOS Agent work under GPL-3.0-only.

### License

The following notice is reproduced from Omarchy's `LICENSE` file:

```text
Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Source: [omacom/omarchy, `quattro` branch](https://github.com/omacom/omarchy/tree/quattro)
