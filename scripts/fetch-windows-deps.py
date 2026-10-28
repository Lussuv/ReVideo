#!/usr/bin/env python3
"""Downloads GStreamer + ffmpeg for Windows from the MSYS2 ucrt64 repo and
unpacks them into a sysroot (default: build/windows/sysroot/ucrt64).

Usage: fetch-windows-deps.py [SYSROOT_PARENT]
"""
import io
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ENV = "ucrt64"
REPO = f"https://repo.msys2.org/mingw/{ENV}"
PREFIX = "mingw-w64-ucrt-x86_64-"
ROOTS = [
    "gstreamer", "gst-plugins-base", "gst-plugins-good", "gst-plugins-bad",
    "gst-plugins-ugly", "gst-libav", "ffmpeg",
]
# Build-time-only or huge optional pieces the player never loads.
SKIP = {"python", "gtk3", "gtk4", "qt5-base", "qt6-base", "opencv", "vulkan-loader-git"}


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url) as r:
        return r.read()


def unzstd(data: bytes) -> bytes:
    return subprocess.run(["zstd", "-dc"], input=data, capture_output=True, check=True).stdout


def load_db() -> dict[str, dict]:
    raw = fetch(f"{REPO}/{ENV}.db")
    if raw[:4] == b"\x28\xb5\x2f\xfd":
        raw = unzstd(raw)
    pkgs, provides = {}, {}
    with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
        for member in tar:
            if not member.name.endswith("/desc"):
                continue
            fields, key = {}, None
            for line in tar.extractfile(member).read().decode().splitlines():
                if line.startswith("%") and line.endswith("%"):
                    key = line.strip("%")
                    fields[key] = []
                elif line and key:
                    fields[key].append(line)
            name = fields["NAME"][0]
            pkgs[name] = fields
            for p in fields.get("PROVIDES", []):
                provides[strip_version(p)] = name
    for alias, name in provides.items():
        pkgs.setdefault(alias, pkgs[name])
    return pkgs


def strip_version(dep: str) -> str:
    for op in (">=", "<=", "=", ">", "<"):
        dep = dep.split(op)[0]
    return dep


def resolve(pkgs: dict[str, dict]) -> list[dict]:
    seen, order, todo = set(), [], [PREFIX + r for r in ROOTS]
    while todo:
        name = strip_version(todo.pop())
        if name.removeprefix(PREFIX) in SKIP or name not in pkgs:
            continue
        pkg = pkgs[name]
        if pkg["NAME"][0] in seen:
            continue
        seen.add(pkg["NAME"][0])
        order.append(pkg)
        todo.extend(pkg.get("DEPENDS", []))
    return order


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "build/windows/sysroot")
    cache = out.parent / "pkg-cache"
    cache.mkdir(parents=True, exist_ok=True)
    pkgs = resolve(load_db())
    total = sum(int(p["CSIZE"][0]) for p in pkgs)
    print(f"{len(pkgs)} Pakete, {total / 1e6:.0f} MB komprimiert")
    for pkg in pkgs:
        filename = pkg["FILENAME"][0]
        archive = cache / filename
        if not archive.exists():
            print(f"  lade {filename}")
            archive.write_bytes(fetch(f"{REPO}/{filename}"))
        with tarfile.open(fileobj=io.BytesIO(unzstd(archive.read_bytes()))) as tar:
            tar.extractall(out, filter="data", members=[m for m in tar if m.name.startswith(f"{ENV}/")])
    print(f"Sysroot: {out / ENV}")


if __name__ == "__main__":
    main()
