#!/usr/bin/env python3
"""Completes the Windows install tree after windeployqt (runs in MSYS2 UCRT64).

- copies every DLL the staged executables, plugins and QML modules import
  (transitively), searching the given directories in order
- copies the license files of all MSYS2 packages the staged files come from into
  STAGE/licenses, plus the ones passed with --license, and writes an overview
- writes the MSYS2 source package names (pkgbase-version) to the --sources file

Usage: stage-windows.py STAGE SEARCH_DIR... --msys-root DIR --license "NAME=FILE"... --sources FILE

MSYS2's Python is a native Windows program: all paths must be Windows paths
(cygpath -w), MSYS2's own files are found below --msys-root.
"""
import argparse
import re
import shutil
import subprocess
from pathlib import Path

PREFIX = "mingw-w64-ucrt-x86_64-"


def imports(binary: Path) -> list[str]:
    out = subprocess.run(["objdump", "-p", str(binary)], capture_output=True, text=True, check=True).stdout
    return re.findall(r"DLL Name: (\S+)", out)


def copy_dependencies(stage: Path, search: list[Path]) -> None:
    available: dict[str, Path] = {}
    for d in reversed(search):  # earlier directories win
        available.update({p.name.lower(): p for p in d.glob("*.dll")})
    present = {p.name.lower() for p in stage.rglob("*.dll")}
    todo = [p for p in stage.rglob("*") if p.suffix.lower() in (".exe", ".dll")]
    while todo:
        for dll in imports(todo.pop()):
            name = dll.lower()
            if name in present or name not in available:
                continue  # system DLL (kernel32, ucrt api sets, …) or already staged
            present.add(name)
            todo.append(Path(shutil.copy2(available[name], stage / "bin")))


def installed_packages(msys_root: Path) -> dict[str, dict[str, str]]:
    """name -> {version, base} from pacman's local database."""
    pkgs = {}
    for desc in (msys_root / "var/lib/pacman/local").glob("*/desc"):
        fields, key = {}, None
        for line in desc.read_text(encoding="utf-8").splitlines():
            if line.startswith("%") and line.endswith("%"):
                key = line.strip("%")
            elif line and key and key not in fields:
                fields[key] = line
        pkgs[fields["NAME"]] = {"version": fields["VERSION"], "base": fields.get("BASE", fields["NAME"])}
    return pkgs


def owners(stage: Path) -> set[str]:
    """MSYS2 packages that own a file with the name of a staged file."""
    listing = subprocess.run(["pacman", "-Ql"], capture_output=True, check=True).stdout.decode("utf-8", "replace")
    by_name: dict[str, str] = {}
    for line in listing.splitlines():
        pkg, _, path = line.partition(" ")
        if pkg.startswith(PREFIX) and path.lower().endswith((".dll", ".exe")):
            by_name.setdefault(Path(path).name.lower(), pkg)
    return {by_name[p.name.lower()] for p in stage.rglob("*") if p.name.lower() in by_name}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", type=Path)
    ap.add_argument("search", type=Path, nargs="+")
    ap.add_argument("--msys-root", type=Path, required=True)
    ap.add_argument("--license", action="append", default=[], help="NAME=FILE")
    ap.add_argument("--sources", type=Path, required=True)
    args = ap.parse_args()

    copy_dependencies(args.stage, args.search)

    licenses = args.stage / "licenses"
    licenses.mkdir(exist_ok=True)
    pkgs = installed_packages(args.msys_root)
    used = sorted(owners(args.stage))
    lines = [
        "ReVideo enthält die folgenden Open-Source-Komponenten unter ihren eigenen Lizenzen.",
        "Der Quellcode genau dieser Versionen liegt jedem Release als",
        "ReVideo-<version>-windows-sources.tar bei:",
        "https://github.com/Lussuv/ReVideo-releases/releases",
        "",
        "Die Bibliotheken liegen als austauschbare DLLs in bin/. ffmpeg.exe (GPL) ist ein",
        "eigenständiges Programm, das ReVideo für Export, Vorschaubilder und Frames aufruft.",
        "",
    ]
    for entry in args.license:
        name, _, file = entry.partition("=")
        target = licenses / re.sub(r"[^A-Za-z0-9.-]+", "-", name).strip("-")
        target.mkdir(exist_ok=True)
        shutil.copy2(file, target)
        lines.append(f"{name}  ->  licenses/{target.name}/")
    for pkg in used:
        short = pkg.removeprefix(PREFIX)
        src = args.msys_root / "ucrt64/share/licenses" / short
        if src.is_dir():
            shutil.copytree(src, licenses / short, dirs_exist_ok=True)
        lines.append(f"{short} {pkgs[pkg]['version']}  ->  licenses/{short}/")
    (licenses / "THIRD-PARTY.txt").write_text("\r\n".join(lines) + "\r\n", encoding="utf-8", newline="")

    # Source file names write an epoch ("2:1.0-1") as "2~1.0-1".
    bases = sorted({f"{pkgs[p]['base']}-{pkgs[p]['version'].replace(':', '~')}" for p in used})
    # Read by a bash loop: LF only.
    args.sources.write_text("\n".join(bases) + "\n", newline="\n")
    size = sum(f.stat().st_size for f in args.stage.rglob("*") if f.is_file())
    print(f"{len(used)} MSYS2-Pakete, {size / 1e6:.0f} MB in {args.stage}")


if __name__ == "__main__":
    main()
