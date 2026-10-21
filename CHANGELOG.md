# Changelog

All notable changes. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow `version=` in `module/module.prop`.

## [0.2.0] - 2026-10-19

Security and boot-safety hardening from an adversarial audit. Upgrade is compatible with 0.1.0
(same state format; managed apps are carried over).

### Security
- `--apk`: the file is copied into the private work directory before any check, and only that
  copy is checked and installed. Before, another app could swap a file on shared storage between
  the identity check and the copy, and get an arbitrary APK installed as a system app.
- `--apk` identity is never proven with `cksum` (CRC32, forgeable); without `cmp` it exits 4.
- As root, the caller's environment is ignored: fixed `PATH` (`su` keeps e.g. Termux's
  app-writable `PATH`), `CDPATH` unset, `SYSTEMIZER_*` test hooks and `NVBASE` ignored. `aapt2`
  is now only found in the module's `bin/` or the system directories.
- CI: actions pinned to commit SHAs, checkout without persisted credentials.

### Fixed (boot safety and recovery)
- Privileged mode fails closed when a requested permission's protection level cannot be parsed
  from the permission table. Before, it was silently left out of the deny list (boot risk under
  `enforce`). `status` reports `UNKNOWN` instead of "up to date" when it cannot check.
- Android 8.x with `enforce`: refuses an allowlist that leaves a requested privileged permission
  ungranted (no deny element exists there); drift is now checked on 8.x too.
- Updates of preinstalled apps (`UPDATED_SYSTEM_APP`, which `pm path` shows only in `/data`) are
  refused instead of getting a second system copy.
- Ctrl-C / hangup can no longer interrupt publishing half way; the previous allowlist is restored
  if the APK rename fails; `sync` after publishing, removing and writing state.
- Lock: atomic hard link to a file that already holds the pid (no empty-pid window that let a
  second run break a live lock).
- Module upgrade also keeps a user-supplied `bin/aapt2`.

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
  single and a split APK, privileged mode with explicit grants, updated-system-app behaviour,
  module upgrade, removal (docs/TESTING.md).

### Not validated yet
- Refresh after a real store update, other devices/ROMs, KernelSU and APatch.
