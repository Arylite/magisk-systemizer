# Design, compatibility and security review

## 1. How Android finds system apps, and what the overlay does

- At boot the package manager scans fixed directories: `/system/app` and `/system/priv-app`,
  plus the same on `/product`, `/vendor`, `/system_ext`, `/odm` from Android 9-10 on. Each
  sub-directory is one package (`base.apk`, plus split APKs, supported since Android 5.0). An app
  found there is a system app; one found in `priv-app` also gets the privileged flag. Apps in
  `/data/app` are user apps (randomized `~~xxxx==/<package>-yyyy==/` directories since Android 11).
- The same package in both places: if the `/data` copy is as new or newer, it runs as an
  "updated system app" and keeps its data; if it is older, Android drops it and the system copy
  runs. Signatures must match. This tool only copies the APKs that are installed, so they do.
- Magisk merges the files under a module's `system/` into `/system` at boot (magic mount). The
  partitions are not written, and the overlay is read at boot, so **every change needs a reboot**.
- **Strategy**: always `/system/app` and `/system/priv-app`. They exist on every supported
  release and Magisk maps them whatever the partition layout. An app that already lives in
  `/product/app`, `/vendor/...` or `/system_ext/...` is refused ("already a system app"); the tool
  never shadows OEM apps. A device without `/system/app` (or `priv-app` for privileged mode) fails
  with exit 4 and a message.

| Android | Privileged permissions of a `priv-app` app | What this tool does |
|---|---|---|
| 5.0 - 7.1 | all granted automatically | no XML; `--grant` is refused (exit 4) as meaningless |
| 8.0 - 8.1 | only those named in `/system/etc/permissions/*.xml`; others not granted (under `enforce`, an unlisted one may stop the boot) | XML with the `--grant` list; no deny element exists, so under `enforce` every requested privileged permission must be granted or the tool refuses (exit 7) |
| 9+ | same, and an unlisted permission can stop the boot when `ro.control_privapp_permissions=enforce` | XML with grants plus an explicit `deny-permission` for every other privileged permission requested |

Source: the AOSP privileged-permission allowlist documentation. This is documented behaviour; only
API 36 (one Pixel 10a) was exercised (see TESTING.md).

## 2. Architecture

```
/data/adb/modules/arylite.systemizer/
  module.prop  lib/*.sh                      code, one concern per file
  system/bin/systemizer                      launcher, becomes /system/bin/systemizer after a reboot
  system/app/<pkg>/base.apk split_N.apk      overlay, system mode
  system/priv-app/<pkg>/...                  overlay, privileged mode
  system/etc/permissions/privapp-permissions-<pkg>.xml    only when needed
  state/<pkg>.conf                           schema, package, mode, source, apks, versioncode, grants
  .work/                                     lock, staging, trash; empty after every command
```

- **Isolation**: one directory and one state file per package, named from the validated package
  name. `remove` derives its paths from the name alone, so a corrupt state file cannot misdirect it.
- **Transactions**: copy and verify (`cmp`, `cksum` fallback) everything in `.work/stage.*`, build
  and re-check the XML, set mode and SELinux label, then publish with renames (atomic on one
  filesystem). The state file is written last. A failure before the renames leaves the old state
  intact; a crash after them leaves an overlay without state, which `install` repairs and
  `doctor` reports.
- **Boot safety order**: the allowlist is published before the APKs and removed after them, so a
  priv-app APK is never visible without its allowlist.
- **No boot work**: no `post-fs-data.sh`, `service.sh` or `uninstall.sh`. Everything lives inside the
  module directory, so Magisk removing the module removes all of it.
- **Module upgrade**: `customize.sh` copies `state/`, `bin/` and the overlay directories from the old
  module (Magisk wipes the new one first). While an upgrade is pending (`update` marker), mutating
  commands refuse, since the pending copy would replace the change.
- **Stale detection**: `status` and `refresh` compare the installed APKs with the overlay byte for
  byte, not by version number.
- **Portability rules**: POSIX sh only. No `local`, arrays, `[[ ]]`, here-documents (mksh needs a
  writable `TMPDIR` for them), `awk`, `sed`, `readlink -f`, BusyBox, or Python on the device.
  `dumpsys` and `pm` output is parsed with `read` and `case`.

## 3. Discovering packages and proving identity

- `pm path <pkg>` gives the APKs (one line each; base and splits). Lines are read whole, so
  spaces are safe. Anything outside the data directory counts as a system app. Mixed or
  malformed output is rejected.
- Splits are copied as a set (`base.apk`, `split_2.apk`, ...) into one directory, which Android
  loads as one package. If the set changes (a language split appears), the overlay is stale.
- `--apk` never trusts a file name. Either the file is byte-identical to the installed APK (so the
  identity comes from `pm`), or the app is not installed and `aapt2`/`aapt` reads the package
  name. A different build of an installed app is refused: its signature cannot be checked without
  extra tools, and a signature mismatch can make Android discard the app data.
- Without `aapt`, the tool says what is missing and exits 4. It never guesses.
- The file is first copied into the private work directory; `aapt`, the byte comparison and the
  overlay all use that copy, so a file on shared storage cannot be swapped between check and use.
- The byte comparison that proves identity needs `cmp`; the `cksum` fallback (CRC32, easy to
  forge) is only used to verify copies, never to prove identity.
- An app whose `dumpsys` flags say `SYSTEM` or `UPDATED_SYSTEM_APP` (an update of a preinstalled
  app; `pm path` only shows its `/data` copy) is refused: a second system copy would duplicate it.

## 4. Compatibility matrix (what was actually validated)

| Capability | Status |
|---|---|
| Logic on a development machine: bash 5.3 and dash, 6 test groups | executed, passing |
| Pixel 10a, Android 16 (API 36), `enforce`: CLI in a scratch directory as the adb shell user (mksh, toybox, real `pm`/`dumpsys`) | executed, passing (TESTING.md tier 2) |
| Parsers against real Android 16 `dumpsys package` and `pm list permissions -f` output | executed (fixtures are trimmed captures) |
| Pixel 10a, Android 16, Magisk 30.7, SELinux Enforcing: real install, magic mount, system mode, updated-system-app behaviour, file labels, reboot persistence, module upgrade, removal | executed (TESTING.md tier 3) |
| Privileged mode with explicit grants, rebooted under `enforce` (Pixel 10a, Android 16) | executed (TESTING.md tier 3) |
| Refresh after a real store update; other devices and ROMs | **not executed** |
| Android 5-15, other OEMs, KernelSU, APatch | **not executed** |
| Split APK directory (4 APKs) accepted by the boot-time scan | executed on Android 16 |
| Apps with native libraries, shared UIDs, or that need special partition labels | **not executed** |

Honest summary: the shell logic, argument handling, transactions and privileged-mode rules are
tested, and system mode (single and split APK) and privileged mode with explicit grants were
verified through a real boot on one device. Other devices, ROMs and a refresh after a real update are not. Do not read this table as universal compatibility.

## 5. Open constraints

- A system app that vanishes (module removed, no user copy) may lose its data. The tool warns and
  requires `--yes`.
- A store update of a privileged app can add a privileged permission after the allowlist was
  written. `status` detects it; nothing can stop the next boot from reading the old allowlist.
  Disable auto-update for privileged apps, or check `status` before rebooting.
- `ro.control_privapp_permissions=disable` makes the platform grant everything; the tool warns.
- Recovery-flash upgrades lose the managed apps (Magisk wipes the module first).
- Dynamic features, APEX packages and apps with a `sharedUserId` shared with a system app are not
  specially handled.
- No free-space check: the overlay duplicates the APKs on `/data`, and root may use the blocks the
  filesystem reserves for the system. A failed copy is removed at once; a huge app on a nearly full
  phone can still leave `/data` very low until it is removed.
- A power cut in the middle of publishing (after `sync` was not reached) can leave the app's
  overlay directory missing: boot-safe, reported by `status` / `doctor`, repaired by `install`.
- `aapt`/`aapt2` (only for `--apk` of an app that is not installed) parses the untrusted APK as root.
- Two runs that both find the same stale lock at the same instant could both take it (needs a
  killed run plus two simultaneous starts).

## 6. Security review

| Area | Finding | Handling |
|---|---|---|
| Privilege | tool runs as root and copies APKs into the system image view | refuses non-root; privileged mode only on `--mode privileged`; grants only from `--grant`; signature-only refused; SELinux never changed; no signature bypass |
| Input to paths | package, permission, mode, option values reach file paths and XML | whitelisted characters plus a strict pattern before any use; destination file names are fixed (`base.apk`, `split_N.apk`), never taken from input |
| Deletion | `rm -rf` on computed paths | `sz_safe_rm` only deletes below the work directory, the two overlay directories, the allowlist directory (with the `privapp-permissions-` prefix) and `state/*.conf`; `..` is refused |
| State files | corrupt or hostile `state/*.conf` | parsed by key, never sourced; every field validated; `remove` ignores it |
| XML | injection or malformed output | names limited to `[A-Za-z0-9._]`; output re-read by `sz_xml_ok`, which accepts only the exact generated shape with at least one entry |
| Environment | `su` keeps the caller's `PATH` (e.g. Termux's, writable by that app); test hooks redirect the code and paths | as root (or when the uid is unknown): fixed `PATH=/system/bin:/system/xbin:/vendor/bin:/debug_ramdisk:/sbin`, `CDPATH` unset, `SYSTEMIZER_*` hooks ignored, `NVBASE` not read |
| Races | two commands; a file replaced during copy; `--apk` swapped on shared storage | lock = hard link to a file already holding the pid (atomic, never empty; stale locks detected); every copy is compared with its source; `--apk` is checked and installed from one private copy |
| Interruption | Ctrl-C / hangup between renames | INT, TERM and HUP are ignored from the first rename until the state is written; if the APK rename fails, the previous allowlist is put back; `sync` after publishing |
| Permission table | a protection level the `grep -A12` window misses would drop a deny entry (boot risk) | fail closed: a requested permission that is defined but has no parsed level aborts privileged mode; `status` reports `UNKNOWN` when it cannot check the allowlist |
| Other modules | clash on the same package | refused when another enabled module ships `system/(priv-)app/<pkg>`; no other module is ever modified (a module that ships the same package under another directory name is not detected) |
| CI supply chain | release job has `contents: write` | third-party actions pinned to commit SHAs, checkout without persisted credentials, ShellCheck download checked by SHA-256 |
| Failure | boot loop | no boot scripts; allowlist ordering; `disable` file / safe mode recover; documented in README |
| Network | none | the tool and the module download nothing |

Residual risk is dominated by what a tool like this can never prove: the first boot with a new
system app on a given ROM, above all in privileged mode, which worked on the one device tried. Test on a device you can recover, with a Magisk disable path ready.
