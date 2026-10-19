# Changelog

All notable changes. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow `version=` in `module/module.prop`.

## [0.1.0] - 2026-10-19

### Added
- `systemizer` command: `list`, `install`, `status`, `refresh`, `remove`, `doctor`, `help`.
- System mode (`/system/app`) and privileged mode (`/system/priv-app`) with a generated
  privapp-permissions allowlist: explicit `--grant`, every other privileged permission denied.
- Split APK support, byte-for-byte verification of every copy, stale detection, idempotent
  install / remove, dry run, interactive selection, meaningful exit codes.
- `--apk` with proven identity (byte-identical to the installed APK, or read with aapt/aapt2).
- Magisk module zip with upgrade carry-over; reproducible `build.py`.
- Tests: unit, CLI scenarios, privileged mode, failure and recovery, `--apk`, module and zip;
  a phone sandbox smoke test; CI (ShellCheck, actionlint, bash/dash/mksh/busybox, build).

### Validated on a device
- Pixel 10a, Android 16, Magisk 30.7, SELinux enforcing: install, magic mount, system mode with a
  single and a split APK, updated-system-app behaviour, module upgrade, removal (docs/TESTING.md).

### Not validated yet
- Privileged mode booting under `enforce`, refresh after a real store update, other devices/ROMs,
  KernelSU and APatch.
