#!/usr/bin/env bash
# Windows-Build in einer MSYS2-UCRT64-Shell (GitHub Actions, windows-latest, siehe
# .github/workflows/release.yml). Setzt scripts/build-windows-deps.sh voraus.
# Ergebnis in dist/: Installer und Quellarchiv der mitgelieferten Fremdkomponenten.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^project(ReVideo VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)
ROOT=$PWD/build/windows
LGPL=$ROOT/lgpl
EXPORT=$ROOT/export
STAGE=$ROOT/stage
mkdir -p dist

PKG_CONFIG_PATH="$LGPL/lib/pkgconfig" cmake -S . -B "$ROOT/app" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$LGPL"
cmake --build "$ROOT/app"
# Der Exporttest läuft gegen die Export-ffmpeg (inkl. libx264).
PATH="$EXPORT/bin:$LGPL/bin:$PATH" ctest --test-dir "$ROOT/app" --output-on-failure

rm -rf "$STAGE" && mkdir -p "$STAGE/bin"
cp "$ROOT/app/ReVideo.exe" "$EXPORT/bin/ffmpeg.exe" "$STAGE/bin/"
windeployqt6 --release --qmldir src/qml --no-translations --no-system-d3d-compiler \
    --no-opengl-sw --dir "$STAGE/bin" "$STAGE/bin/ReVideo.exe"
# Python aus MSYS2 ist ein Windows-Programm: alle Pfade als Windows-Pfade übergeben.
w() { cygpath -w "$1"; }
python -I scripts/stage-windows.py "$(w "$STAGE")" "$(w "$LGPL/bin")" "$(w /ucrt64/bin)" \
    --msys-root "$(w /)" \
    --license "ReVideo (GPL-3.0)=$(w "$PWD/LICENSE")" \
    --license "ffmpeg (LGPL, DLLs)=$(w "$LGPL/licenses/ffmpeg/COPYING.LGPLv2.1")" \
    --license "ffmpeg (GPL, ffmpeg.exe)=$(w "$EXPORT/licenses/ffmpeg/COPYING.GPLv2")" \
    --license "mpv (LGPL)=$(w "$LGPL/licenses/mpv/LICENSE.LGPL")" \
    --sources "$(w "$ROOT/msys2-sources.txt")"

# Quellcode aller mitgelieferten Fremdkomponenten (LGPL/GPL verlangen ihn).
SOURCES=$ROOT/sources/ReVideo-$VERSION-windows-sources
rm -rf "$ROOT/sources" && mkdir -p "$SOURCES/msys2"
cp "$ROOT"/src/*.tar.* scripts/build-windows-deps.sh scripts/build-windows.sh "$SOURCES/"
while read -r pkg; do
    curl -sSfL -o "$SOURCES/msys2/$pkg.src.tar.zst" "https://repo.msys2.org/mingw/sources/$pkg.src.tar.zst"
done < "$ROOT/msys2-sources.txt"
tar -cf "dist/ReVideo-$VERSION-windows-sources.tar" -C "$ROOT/sources" "ReVideo-$VERSION-windows-sources"

makensis -V2 -DVERSION="$VERSION" -DSTAGE="$(w "$STAGE")" \
    -DOUTFILE="$(w "$PWD/dist/ReVideo-$VERSION-setup.exe")" packaging/windows/installer.nsi
ls -lh dist/
