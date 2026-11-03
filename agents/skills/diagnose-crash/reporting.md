# Reporting a Crash Upstream to CachyOS

Read this only after concluding that a crash is genuinely CachyOS's to fix.

## Is it even CachyOS's bug?

Be strict here. CachyOS is an Arch-based distribution, so a crash inside a
third-party application — a file manager, a browser, a KDE or Qt library — is
almost always an upstream bug in **that** project, not in CachyOS.

CachyOS's sphere of control is roughly:

- the `linux-cachyos` kernels and their patches
- the packages it builds itself — `pacman -Qi <package>` shows `Packager`
  CachyOS, and `pacman -Si` lists the CachyOS repository (`cachyos`,
  `cachyos-v3`, `cachyos-extra-v3`, ...) beside the Arch one
- how it builds them: the x86-64-v3 and v4 rebuilds, compiler and LTO/PGO flags
- its settings packages (`cachyos-settings`, `cachyos-kde-settings`), `chwd`
  profiles, Kernel Manager, the installer and ISO

A crash in a program CachyOS merely installs from Arch's repositories is **not**
a CachyOS bug unless CachyOS's own packaging or configuration is implicated.
A crash that only happens with the CachyOS build of a package, and not with
Arch's build or upstream's, is implicated. Establish that rather than assume it.

If it is not CachyOS's, say so and stop. Suggesting the right upstream project is
useful; filing there yourself is not part of this.

## Where it goes

Pick the tracker that owns the broken part, all under <https://github.com/CachyOS>:

| Broken part | Tracker |
| --- | --- |
| A kernel, a `linux-cachyos*` build | [`linux-cachyos`](https://github.com/CachyOS/linux-cachyos/issues) |
| A package CachyOS builds, its flags or repository | [`CachyOS-PKGBUILDS`](https://github.com/CachyOS/CachyOS-PKGBUILDS/issues) |
| System settings (sysctl, udev, services) | [`CachyOS-Settings`](https://github.com/CachyOS/CachyOS-Settings/issues) |
| KDE Plasma defaults | [`cachyos-kde-settings`](https://github.com/CachyOS/cachyos-kde-settings/issues) |
| Anything else in the distribution | [`distribution`](https://github.com/CachyOS/distribution/issues) |

`distribution` exists to take general bugs against CachyOS. The CachyOS forum
also has a bug report category (<https://discuss.cachyos.org/c/feedback/bugreports/10>).
A crash in **this tool** — the `cachyos-agent` commands and the skills it
installs — belongs in <https://github.com/keiranhaax/CachyOS-Agent/issues>.

## Three conditions, all required

1. **It is a verified bug in CachyOS's sphere**, established on evidence. Issues
   are for verified bugs only. An "is this even a bug?" belongs on the forum at
   <https://discuss.cachyos.org> or the CachyOS Discord, which the issue
   templates link to.
2. **The user has explicitly agreed.** Show them the exact title and body you
   propose, and wait for a yes. Never file unprompted.
3. **The machine can file it** — `gh auth status` must succeed. If `gh` is missing
   or unauthenticated, do not install or authenticate it. Say so, and hand the
   user the finished text to submit themselves.

## Search before filing

A duplicate issue costs a maintainer more time than no report at all.

```bash
gh search issues --repo CachyOS/distribution "<program> crash"
gh issue list --repo CachyOS/distribution --state all --search "<signal> <program>"
```

Use the repository from the table above. Search on the crashing program, the
signal, and distinctive symbols from the backtrace — not on the wording of the
title you were about to write.

`gh search issues` accepts only `open` or `closed` for `--state`, and errors on
anything else. Leaving it off searches both, which is what you want here.

Include **closed** issues. A matching issue closed as fixed, when the crash still
reproduces on a current system, is a regression — and reporting that is worth far
more than another duplicate.

## Adding to an existing report

If a plausible match comes back, read it properly first:

```bash
gh issue view <number> --repo CachyOS/distribution --comments
```

Confirm it is genuinely the same failure. The same program crashing is not the
same bug if the trigger or the stack differs.

If it is the same, add to that issue rather than opening a new one — but only
when you have something the thread does not already contain: a different
reproduction, a symbolized stack where it has none, a narrower trigger, a version
where it regressed.

A comment that only says the bug happens to you too is noise. If that is all you
have, tell the user so and file nothing.

```bash
gh issue comment <number> --repo CachyOS/distribution --body "..."
```

## Filing a new issue

Only when the search turns up nothing that matches:

```bash
gh issue create --repo CachyOS/distribution --title "[Bug]: ..." --body "..."
```

The repositories above use an issue form, which `gh issue create --body` does
not fill in. Prefix the title with `[Bug]: ` and cover the form's fields in the
body: kernel (`uname -r`), desktop environment, CPU, GPU and driver, a
description, steps to reproduce, expected and actual behaviour, and logs.

For the logs, the templates ask for the output of `sudo cachyos-bugreport.sh`
(it gathers dmesg, the journal and hardware information, and asks before it
uploads the log to paste.cachyos.org). It needs root, so do not run it: give the
user the command and ask them to paste the link it prints. Add the
symbolized backtrace from your own diagnosis, and say which package and
repository the crashing binary came from.

`gh` cannot attach media. If a screenshot would help, save one and give the user
the path to drag into the web form.

## Signing

End the issue or comment with a line naming the model and agent harness that
produced it, so a human reader knows it was machine-authored:

> Filed by \<model name\> via \<agent harness\>.

Use your actual model and harness names. If you are not certain of them, say so
plainly rather than inventing a version string.

---

Adapted from the diagnose-crash skill in Omarchy (MIT, Copyright (c) David
Heinemeier Hansson); see `THIRD_PARTY_NOTICES.md`.
