# Test plan and results

Three tiers. A line says "executed" only if it was run and passed; the rest is marked
"not executed".

| Tier | Command | Needs |
|---|---|---|
| 1. Development machine | `sh tests/run.sh` | a POSIX shell (bash and dash used), `unzip`, Python 3 for the zip checks |
| 2. Phone sandbox | `sh tests/device-smoke.sh [serial]` | adb and a phone; no root; deletes its scratch directory |
| 3. Rooted device | by hand, below | root, a recoverable phone |

## Tier 1 - fake device (executed)

`tests/harness.sh` builds a throw-away device per scenario: a copy of the module, a fake `/system`,
fake `pm`, `dumpsys`, `getprop`, `getenforce`, and fake apps under a randomized
`~~r1==/<pkg>-h1==/` path. Fixtures in `tests/fixtures` are trimmed captures of real Android 16
output. Mutating the code (for example making the byte comparison always succeed) makes tests fail.

| Required case | Where | Status |
|---|---|---|
| Valid and invalid package and permission names | `t-unit`, `t-cli` | executed |
| APK path discovery, randomized paths, spaces in paths | `t-cli` | executed |
| Missing APKs | `t-fail` | executed |
| Split APKs (install, changed set, refresh) | `t-cli` | executed |
| System and privileged modes, allowlist content, grants, denies | `t-priv` | executed |
| Android 7 / 8.1 / 9+ rules, `disable` property, no priv-app dir | `t-priv` | executed (simulated properties) |
| Repeated install and remove (idempotent) | `t-cli` | executed |
| Refresh after an update, stale detection, `--all`, drift of privileged permissions | `t-cli`, `t-priv` | executed |
| Removal then reinstall, remove without a user copy | `t-cli` | executed |
| Missing optional tools: no aapt, no cksum/cmp, no getprop, dumpsys silent | `t-apk`, `t-unit`, `t-fail`, `t-priv` | executed (no chcon binary: not tested) |
| Copy failure leaves no partial install (stand-in for a full or read-only disk) | `t-fail` | executed; a real read-only mount is **not** simulated |
| Unsupported layout (no `/system/app`, no `priv-app`) | `t-fail`, `t-priv` | executed |
| Malformed state files and XML | `t-unit`, `t-fail` | executed |
| Interrupted run leftovers, stale and live lock, other module clash | `t-fail` | executed |
| SELinux enforcing with a failing `chcon` is fatal, permissive is not | `t-fail` | executed with fakes; real labels **not executed** |
| Magisk upgrade path (`customize.sh`), zip structure, reproducible build, build refusals | `t-module` | executed with stubbed Magisk functions |
| Source hygiene: 150-line limit, ASCII, LF, no `eval`/`local`/`[[`, `-n` syntax check | `run.sh` | executed |
| ShellCheck 0.11.0 on the module code (clean), actionlint 1.7.12 on the workflows (clean) | CI `lint` job | executed locally; CI also runs them |
| mksh and busybox ash on Linux | CI `test` job (`SHELLS="bash dash mksh bbsh"`) | runs in CI; not available on the development machine |

Result of the last full run (bash 5.3 and dash, Windows Git Bash): per shell,
unit 74, cli 83, failures 55, apk 28, privileged 55, module 28 checks, all passing.
The fake `pm` and `dumpsys` only write to a pipe, like system_server under SELinux (see below).

## Tier 2 - phone sandbox

`device-smoke.sh` pushes the module to `/data/local/tmp`, runs the CLI as the adb **shell** user with
the phone's own mksh, toybox, and real `pm`/`dumpsys`, against a fake `/system` in that directory.
It checks version/doctor/list, errors (bad name, unknown package), dry run, install, byte-for-byte
copy of the real APK, idempotence, status, a real split-APK app, a privileged plan and an explicit
grant computed from the real permission table (it finds an installed app that requests privileged
permissions), a refused grant, and remove. Nothing outside the scratch directory is changed; it
does not install the module, use `su`, or reboot.

Last run on the Pixel 10a (Android 16): **35 passed, 0 failed**, including a privileged install and an
explicit grant on an installed app that really requests privileged permissions.

## Tier 3 - rooted device

Executed by hand on 2026-10-19: Pixel 10a, Android 16 (API 36), Magisk 30.7, SELinux Enforcing,
`ro.control_privapp_permissions=enforce`, with `busybox-ndk` as the only other module.

| Step | Result |
|---|---|
| Install the zip with `magisk --install-module`, reboot | executed: installer ran `customize.sh`; `/system/bin/systemizer` is mounted; `doctor`: 0 failures |
| System mode, single APK (Google Translate): install, reboot | executed: `flags=[ SYSTEM ... UPDATED_SYSTEM_APP ]`, hidden system copy at `/system/app/<pkg>`, same appId, app data intact, listed by `pm list packages -s` |
| Overlay files | executed: mode 0644, label `u:object_r:system_file:s0`, no SELinux change |
| Module upgrade over a managed app, reboot | executed: state and overlay carried over, still `Active: yes`; a command run before the reboot was refused (exit 7) |
| `remove` twice (second is a no-op), reboot | executed: back to a plain user app, no hidden system copy, data intact |
| Split-APK app (Google Keep, 4 APKs): install, reboot, remove, reboot | executed: the boot scan loaded the directory as one package with all 4 splits; restored afterwards |
| Privileged mode booting under `enforce` | **not executed**: a wrong allowlist can stop the boot; needs an explicit go-ahead and a recovery plan |
| Refresh after a real store update, recovery drill, removal from the Magisk app | **not executed** |
| Other Android versions, ROMs, KernelSU, APatch | **not executed** |

Defects only the phone could show (both fixed, the first now has a regression test):

1. `pm` and `dumpsys` make system_server write to the stdout they are given, which cannot be a file
   under `/data/adb` (SELinux `adb_data_file`). `pm path` silently failed and the tool answered
   "package not installed". Output now goes through a pipe (`sz_capture`).
2. After a Magisk-app style install the files stay in `modules_update` until the reboot, so the
   "before the first reboot" hint printed by `customize.sh` was wrong; it is gone.

Also learned: right after a reboot `pm` can answer before the package manager is ready, and the tool
then fails safely (exit 3). Wait for `sys.boot_completed` and a working `pm`.

## Still to do on a device

Privileged mode under `enforce` (on a phone you can recover, with
`touch /data/adb/modules/arylite.systemizer/disable` possible from recovery or adb; check
`dumpsys package` grants and `logcat | grep -i privapp`), a refresh after a real update, the
recovery drill, and a second ROM.
