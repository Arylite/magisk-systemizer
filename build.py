#!/usr/bin/env python3
"""Build the installable Magisk module ZIP from module/ (deterministic, stdlib only).

    python build.py [--out DIR]      # default: dist/
"""
import argparse
import hashlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "module"
REQUIRED = [
    "module.prop", "customize.sh", "lib/core.sh", "system/bin/systemizer",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]
EXECUTABLE = {"system/bin/systemizer", "META-INF/com/google/android/update-binary"}
SKIP = {".work", "state"}  # runtime directories, never shipped
STAMP = (1980, 1, 1, 0, 0, 0)  # fixed timestamp: same input, same bytes


def fail(msg):
    sys.exit("build: " + msg)


def files(src):
    found = []
    for p in sorted(src.rglob("*")):
        rel = p.relative_to(src)
        if p.is_file() and not (set(rel.parts) & SKIP):
            found.append(rel.as_posix())
    return found


def read_prop(data):
    prop = {}
    for line in data.decode("ascii").splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            prop[key] = value
    if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9._-]+", prop.get("id", "")):
        fail("module.prop: invalid id")
    if not prop.get("versionCode", "").isdigit():
        fail("module.prop: versionCode must be an integer")
    for key in ("name", "version", "author", "description"):
        if not prop.get(key):
            fail("module.prop: missing " + key)
    return prop


def build(src, out_dir):
    names = files(src)
    for need in REQUIRED:
        if need not in names:
            fail("missing " + need)
    contents = {}
    for name in names:
        data = (src / name).read_bytes()
        if b"\r" in data:
            fail(name + ": CR found, use LF line endings")
        try:
            data.decode("ascii")
        except UnicodeDecodeError:
            fail(name + ": non-ASCII character")
        contents[name] = data
    prop = read_prop(contents["module.prop"])
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / "{}-{}.zip".format(prop["id"], prop["version"])
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for name in names:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100755 if name in EXECUTABLE else 0o100644) << 16
            z.writestr(info, contents[name])
    return target, prop


def verify(target, prop):
    with zipfile.ZipFile(target) as z:
        if z.testzip() is not None:
            fail("corrupt zip")
        names = z.namelist()
        if any("\\" in n or n.startswith("/") for n in names):
            fail("entry names must use forward slashes and be relative")
        for need in REQUIRED:
            if need not in names:
                fail("zip lacks " + need)
        if z.read("META-INF/com/google/android/updater-script").strip() != b"#MAGISK":
            fail("updater-script must contain only #MAGISK")
        if read_prop(z.read("module.prop"))["id"] != prop["id"]:
            fail("module.prop id mismatch")
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=str(ROOT / "dist"))
    ap.add_argument("--src", default=str(SRC), help="module tree (for tests)")
    args = ap.parse_args()
    target, prop = build(Path(args.src), Path(args.out))
    names = verify(target, prop)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    print(f"{target} ({len(names)} files)\nsha256 {digest}")


if __name__ == "__main__":
    main()
