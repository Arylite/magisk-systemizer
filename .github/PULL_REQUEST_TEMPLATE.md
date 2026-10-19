## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `sh tests/run.sh` passes (it enforces the rules below)
- [ ] Every script file is at most 150 lines; new code goes in a module under `module/lib/`
- [ ] POSIX sh only (no `local`, arrays, `[[ ]]`, here-documents, `awk`), ASCII only
- [ ] A test covers the change (`tests/t-*.sh`); a bug fix has a test that failed before
- [ ] README / docs / CHANGELOG updated when behaviour changes
- [ ] Not tested on a rooted device? Say so here: <!-- what you ran, on which Android -->
