# Security policy

This tool runs as root and puts APKs into the system image view, so reports are taken seriously.

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private reporting:
**Security > Report a vulnerability** on this repository. Include the Android version, the root
solution, the command, and what an attacker gains. You will get an answer within a week.

## In scope

- Anything that makes the tool delete or write outside its own module directory.
- Grants or allowlist entries the user did not ask for, or a way around the signature-level refusal.
- Injection through package names, permission names, `--apk` paths, or state files.
- Anything that can leave a device unable to boot without an obvious recovery.
- Influence of the caller's environment on a root run. As root the tool ignores the `SYSTEMIZER_*`
  test hooks, `CDPATH` and the inherited `PATH` (it uses `/system/bin:/system/xbin:/vendor/bin:/debug_ramdisk:/sbin`).

## Out of scope

- An attacker who already runs code as root, or can write to `/data/adb`.
- Problems in Magisk, Android, or in the apps you choose to systemize.

The design and threat review lives in [docs/DESIGN.md](docs/DESIGN.md#6-security-review).
