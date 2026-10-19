# Contributing

## Set up

Needs a POSIX shell (bash and dash are what CI uses), `unzip`, and Python 3 for the zip checks.

```sh
sh tests/run.sh            # hygiene + every test under each shell in $SHELLS (default: bash dash)
SHELLS="bash dash mksh" sh tests/run.sh
python build.py            # dist/arylite.systemizer-<version>.zip
sh tests/device-smoke.sh   # optional: a real phone over adb, scratch directory, no root
```

CI also runs ShellCheck (the module code must be clean) and `actionlint`.

## Rules (enforced by `tests/run.sh`)

- **Files stay small**: at most 150 lines per script. New behaviour goes in its own module under
  `module/lib/`, loaded by the launcher list in `module/system/bin/systemizer`.
- **Device-portable shell**: POSIX sh as Android's mksh and Magisk's ash run it. No `local`,
  arrays, `[[ ]]`, here-documents, `eval`, `source`, `awk`, or `sed` in the module code.
- **ASCII only** in code, comments, docs and messages. LF line endings.
- **No hardcoding**: no package names, devices, Android versions or paths that can be detected.
- **Safe by default**: least privilege, nothing granted without an explicit flag, validate before
  changing anything, never touch SELinux or signatures.

## Changes

- Add a test with the change. A bug fix starts with a test that fails.
- Be honest in the PR about what was only tested with fakes. Real mount and reboot behaviour is
  tier 3 in [docs/TESTING.md](docs/TESTING.md).
- Commit messages: `type: short summary` (`feat`, `fix`, `docs`, `test`, `ci`, `refactor`).
- Update `CHANGELOG.md` for anything a user would notice.
