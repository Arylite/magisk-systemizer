# App Systemizer

[![CI](https://github.com/Arylite/magisk-systemizer/actions/workflows/ci.yml/badge.svg)](https://github.com/Arylite/magisk-systemizer/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
![Magisk 20.4+](https://img.shields.io/badge/Magisk-20.4%2B-green.svg)

A Magisk module that turns any installed Android app into a system app (or a privileged system
app) through the Magisk overlay. Install the module once, then use the `systemizer` command for
as many apps as you like. Nothing is hardcoded: no package name, device, Android version or
architecture. The real system partitions are never modified.

Module id `arylite.systemizer` - [design and security review](docs/DESIGN.md) -
[test plan and results](docs/TESTING.md)

## Requirements

- Magisk 20.4 or newer (KernelSU / APatch may work, see the compatibility notes in DESIGN.md).
- Android 5.0 (API 21) or newer, with `/system/app` (and `/system/priv-app` for privileged mode).
- A root shell. Only POSIX tools every Android has are needed: `sh pm cp mv rm grep cmp|cksum`.
  Optional: `dumpsys` + `getprop` (privileged mode), `chcon` (SELinux label), `aapt2`/`aapt`
  (`--apk` for an app that is not installed yet).

## Install

1. `python build.py` builds `dist/arylite.systemizer-v0.1.0.zip` (same bytes every time).
2. Magisk app > Modules > Install from storage > pick the zip > reboot.
3. In a root shell (Termux + `su`, or `adb shell su`): `systemizer help`.

The command only exists after the reboot that finishes the Magisk install.

## Getting started

Open a root shell (`adb shell` then `su`, or Termux then `su`).

1. **Check the device**: `systemizer doctor` should end with `0 failure(s)`.
2. **Pick an app that is already installed**: `systemizer install` shows a numbered list, asks which
   one, then asks to confirm. Or name it: `systemizer install com.example.app`.
   Add `--dry-run` first to see the plan without changing anything.
3. **Reboot**, then check: `systemizer status com.example.app` shows `Active: yes`.
4. **After the app was updated** by the store: `systemizer status` says `STALE`, so run
   `systemizer refresh --all` and reboot.
5. **Undo**: `systemizer remove com.example.app`, then reboot.

### Coming from Terminal Systemizer

Terminal Systemizer's README documents only the entries on the left (check `systemize -h` on your
device for more). Everything else in the right column has no Terminal Systemizer counterpart.

| Terminal Systemizer | App Systemizer |
|---|---|
| `su`, then `systemize` and choose the app from the list | `su`, then `systemizer install` (numbered list, then confirm) |
| `systemize -h` | `systemizer help`, or `systemizer <command> -h` |
| `systemize -f` (SELinux handling) | none: this tool never changes SELinux; it labels its files with `chcon` and `doctor` reports the state |
| `logs` entry in the menu (uploads logs, gives a link) | `systemizer doctor` prints a local report; nothing is ever uploaded |
| scripted use is not documented | `systemizer install com.example.app --yes`, with exit codes |
| | `systemizer list`, `status`, `refresh`, `remove`, `--dry-run`, `--mode privileged` |

What is different: the app is copied once and verified byte for byte, each app is isolated and
tracked, a changed app is detected (`status` / `refresh`), repeating a command is safe, and
privileged mode never grants anything you did not name with `--grant`.

## Commands

| Command | What it does |
|---|---|
| `systemizer list [--managed]` | User apps, or only the apps managed by this module |
| `systemizer install [PACKAGE] [options]` | Systemize an app. With no package and a terminal, choose from a numbered list |
| `systemizer status [PACKAGE]` | Summary of managed apps, or the details of one (exit 6 when stale) |
| `systemizer refresh PACKAGE` / `--all` | Re-copy the APKs after the app was updated |
| `systemizer remove PACKAGE [--yes]` | Stop managing an app |
| `systemizer doctor` | Check the device and the module state |

Install options: `--package NAME`, `--apk PATH`, `--mode system|privileged`, `--grant PERM`
(repeatable, privileged only), `--yes`, `--dry-run`.

```sh
systemizer install com.example.app                       # system app (default, least privilege)
systemizer install com.example.app --dry-run             # prepare and verify, change nothing
systemizer install com.example.app --mode privileged --grant android.permission.INSTALL_PACKAGES
systemizer install --apk /sdcard/app.apk --package com.example.app   # must equal the installed APK
systemizer status                                        # all managed apps
systemizer refresh --all                                 # after the Play Store updated them
systemizer remove com.example.app
```

Every change takes effect after a reboot. Exit codes: `0` ok, `1` failure, `2` usage,
`3` not found, `4` unsupported device or setup, `5` verification failed, `6` stale (run
`refresh`), `7` refused for safety. Repeating `install` or `remove` is safe and does nothing
the second time. Without a terminal, nothing is asked: pass the package, and `--yes` where a
confirmation is needed.

## System, privileged, and protected permissions

1. **System app** (`/system/app`): survives a factory reset, cannot be uninstalled by the user,
   but gets no extra permission.
2. **Privileged app** (`/system/priv-app`): may *request* privileged permissions
   (`signature|privileged`), such as `INSTALL_PACKAGES`. From Android 8 it only gets those that
   an allowlist XML names, and from Android 9 an unlisted one can stop the device booting.
   So this tool writes the XML itself: the permissions you pass with `--grant` are allowed, and
   every other privileged permission the app asks for is explicitly denied. Nothing is granted
   that you did not name. Privileged mode needs the app installed and is never the default.
3. **Signature-only permissions** (no `privileged` flag): need the platform signing key. No
   allowlist can grant them and this tool never tries (`--grant` fails with exit 4).

It never disables SELinux and never touches signature checks.

## Updating, removing, recovering

- **Module update**: install the new zip from the Magisk app. Managed apps are carried over.
  Reboot before systemizing anything else (the tool refuses while an update is pending).
  Flashing from recovery wipes the old module first, so managed apps are not kept.
- **Remove an app**: `systemizer remove PACKAGE`, reboot. If no user copy of the app is
  installed, Android removes it at the next boot and may delete its data, so you must pass
  `--yes`. Install the app normally first to avoid that.
- **Remove the module**: Magisk app > Modules > remove, reboot. The app data is not touched.
- **Boot problem**: from adb or a recovery shell, `touch /data/adb/modules/arylite.systemizer/disable`
  and reboot (this disables only this module). `magisk --remove-modules` also works but removes
  ALL modules. Magisk safe mode disables modules too. This module has no boot script, so only
  the overlay content can affect booting.
- **After an app update** with a privileged app: run `systemizer status`. If the app now asks for a
  new privileged permission, `status` says so (exit 6) and `refresh` adds it to the denied list.
  Turn off automatic updates for privileged apps if you cannot check before each reboot.

## Development

```sh
python build.py                 # the zip, in dist/
sh tests/run.sh                 # all dev-machine tests, under bash and dash
sh tests/device-smoke.sh        # real phone over adb, in a scratch directory, no root
```

Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).
Release: push a tag equal to the module version (`v0.1.0`); the release workflow tests, builds and
attaches the zip and its checksum.

Source layout: `module/system/bin/systemizer` is a short launcher; `module/lib/*.sh` hold the
code, one concern per file, none over 150 lines (`tests/run.sh` enforces it).

## License

Copyright (C) 2026 Arylite. GNU General Public License v3.0: you may use, change and
share it, you must credit the author and keep the copyright notices, and anything you distribute
based on it must stay open source under the same license (see [LICENSE](LICENSE)). The license does
not forbid selling copies: that restriction cannot exist in an open source license.
