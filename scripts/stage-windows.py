#!/usr/bin/env python3
"""Copies ReVideo.exe, ffmpeg, the GStreamer plugins and exactly the DLLs they
import (transitively) from the sysroot into a relocatable install tree.

Usage: stage-windows.py EXE SYSROOT STAGE_DIR

GStreamer finds its plugins relative to libgstreamer-1.0-0.dll (bin/../lib),
so the tree keeps the MSYS2 layout: bin/, lib/gstreamer-1.0/, libexec/.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

OBJDUMP = shutil.which("x86_64-w64-mingw32-objdump") or "objdump"
# Plugins that drag in large stacks (GTK, Qt, Python, OpenCV, …) the player never uses.
SKIP_PLUGINS = re.compile(r"gtk|qt|python|opencv|vulkan|webrtc|nice|srt|rtmp|onnx|whisper|aja|decklink|codec2json")


def imports(binary: Path) -> list[str]:
    out = subprocess.run([OBJDUMP, "-p", str(binary)], capture_output=True, text=True, check=True).stdout
    return re.findall(r"DLL Name: (\S+)", out)


def main() -> None:
    exe, sysroot, stage = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    if stage.exists():
        shutil.rmtree(stage)
    (stage / "bin").mkdir(parents=True)
    (stage / "lib/gstreamer-1.0").mkdir(parents=True)
    (stage / "libexec/gstreamer-1.0").mkdir(parents=True)

    roots = [shutil.copy2(exe, stage / "bin/ReVideo.exe")]
    for tool in ("ffmpeg.exe", "ffprobe.exe"):
        roots.append(shutil.copy2(sysroot / "bin" / tool, stage / "bin"))
    roots.append(shutil.copy2(sysroot / "libexec/gstreamer-1.0/gst-plugin-scanner.exe", stage / "libexec/gstreamer-1.0"))
    for plugin in sorted((sysroot / "lib/gstreamer-1.0").glob("*.dll")):
        if not SKIP_PLUGINS.search(plugin.name):
            roots.append(shutil.copy2(plugin, stage / "lib/gstreamer-1.0"))

    available = {p.name.lower(): p for p in (sysroot / "bin").glob("*.dll")}
    copied: set[str] = set()
    todo = [Path(r) for r in roots]
    while todo:
        for dll in imports(todo.pop()):
            name = dll.lower()
            if name in copied or name not in available:
                continue  # system DLL (kernel32, ucrt api sets, …) or already staged
            copied.add(name)
            todo.append(Path(shutil.copy2(available[name], stage / "bin")))

    size = sum(f.stat().st_size for f in stage.rglob("*") if f.is_file())
    print(f"{len(roots)} Einstiegspunkte, {len(copied)} DLLs, {size / 1e6:.0f} MB in {stage}")


if __name__ == "__main__":
    main()
