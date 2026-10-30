#!/usr/bin/env bash
# Windows-Build in einer MSYS2-UCRT64-Shell (GitHub Actions, windows-latest, siehe
# .github/workflows/release.yml). Ergebnis in dist/: Installer und Quellarchiv der
# mitgelieferten Fremdkomponenten.
#
# Lizenzen: ffmpeg und mpv werden hier als LGPL gebaut und als DLLs neben die App
# gelegt (austauschbar). Die Export-ffmpeg.exe enthält x264 und ist damit GPL; die
# App startet sie nur als eigenes Programm und linkt nie dagegen.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^project(ReVideo VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)
FFMPEG=9.0.2
FFMPEG_SHA=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
MPV=0.41.0
MPV_SHA=ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209

ROOT=$PWD/build/windows
SRC=$ROOT/src
LGPL=$ROOT/lgpl        # ffmpeg-DLLs + libmpv für die App
EXPORT=$ROOT/export    # ffmpeg.exe (GPL) für den Export
STAGE=$ROOT/stage
JOBS=$(nproc)
mkdir -p "$SRC" dist

fetch() { # url sha256 file
    [ -f "$SRC/$3" ] || curl -sSfL -o "$SRC/$3" "$1"
    echo "$2  $SRC/$3" | sha256sum -c -
}
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz" "$FFMPEG_SHA" "ffmpeg-$FFMPEG.tar.xz"
fetch "https://github.com/mpv-player/mpv/archive/refs/tags/v$MPV.tar.gz" "$MPV_SHA" "mpv-$MPV.tar.gz"

# ffmpeg als LGPL-DLLs (kein --enable-gpl, kein --enable-nonfree)
if [ ! -f "$LGPL/lib/pkgconfig/libavcodec.pc" ]; then
    rm -rf "$ROOT/ffmpeg-lgpl" && mkdir -p "$ROOT/ffmpeg-lgpl"
    tar -xf "$SRC/ffmpeg-$FFMPEG.tar.xz" -C "$ROOT/ffmpeg-lgpl" --strip-components=1
    (cd "$ROOT/ffmpeg-lgpl" && ./configure --prefix="$LGPL" --enable-shared --disable-static \
        --disable-programs --disable-doc --disable-debug --enable-libdav1d \
        && make -j"$JOBS" && make install)
fi

# libmpv ohne GPL-Teile, gegen das LGPL-ffmpeg
if [ ! -f "$LGPL/lib/pkgconfig/mpv.pc" ]; then
    rm -rf "$ROOT/mpv-src" "$ROOT/mpv-build" && mkdir -p "$ROOT/mpv-src"
    tar -xf "$SRC/mpv-$MPV.tar.gz" -C "$ROOT/mpv-src" --strip-components=1
    PKG_CONFIG_PATH="$LGPL/lib/pkgconfig" meson setup "$ROOT/mpv-build" "$ROOT/mpv-src" \
        --prefix="$LGPL" --buildtype=release -Dgpl=false -Dlibmpv=true -Dcplayer=false \
        -Dlua=disabled -Djavascript=disabled -Dmanpage-build=disabled -Dhtml-build=disabled \
        -Dpdf-build=disabled
    meson install -C "$ROOT/mpv-build"
fi

# Export-ffmpeg: libav* statisch in der exe, damit sie nicht mit den LGPL-DLLs kollidiert
if [ ! -f "$EXPORT/bin/ffmpeg.exe" ]; then
    rm -rf "$ROOT/ffmpeg-gpl" && mkdir -p "$ROOT/ffmpeg-gpl"
    tar -xf "$SRC/ffmpeg-$FFMPEG.tar.xz" -C "$ROOT/ffmpeg-gpl" --strip-components=1
    (cd "$ROOT/ffmpeg-gpl" && ./configure --prefix="$EXPORT" --disable-shared --enable-static \
        --enable-gpl --enable-libx264 --enable-libdav1d --disable-ffplay --disable-ffprobe \
        --disable-doc --disable-debug \
        && make -j"$JOBS" && make install)
fi

PKG_CONFIG_PATH="$LGPL/lib/pkgconfig" cmake -S . -B "$ROOT/app" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$LGPL"
cmake --build "$ROOT/app"
# Der Exporttest läuft gegen die Export-ffmpeg (inkl. libx264).
PATH="$EXPORT/bin:$LGPL/bin:$PATH" ctest --test-dir "$ROOT/app" --output-on-failure

rm -rf "$STAGE" && mkdir -p "$STAGE/bin"
cp "$ROOT/app/ReVideo.exe" "$EXPORT/bin/ffmpeg.exe" "$STAGE/bin/"
windeployqt6 --release --qmldir src/qml --no-translations --no-system-d3d-compiler \
    --no-opengl-sw --dir "$STAGE/bin" "$STAGE/bin/ReVideo.exe"
python -I scripts/stage-windows.py "$STAGE" "$LGPL/bin" /ucrt64/bin \
    --license "ffmpeg (LGPL, DLLs)=$ROOT/ffmpeg-lgpl/COPYING.LGPLv2.1" \
    --license "ffmpeg (GPL, ffmpeg.exe)=$ROOT/ffmpeg-gpl/COPYING.GPLv2" \
    --license "mpv (LGPL)=$ROOT/mpv-src/LICENSE.LGPL" \
    --sources "$ROOT/msys2-sources.txt"

# Quellcode aller mitgelieferten Fremdkomponenten (LGPL/GPL verlangen ihn).
SOURCES=$ROOT/sources/ReVideo-$VERSION-windows-sources
rm -rf "$ROOT/sources" && mkdir -p "$SOURCES/msys2"
cp "$SRC/ffmpeg-$FFMPEG.tar.xz" "$SRC/mpv-$MPV.tar.gz" scripts/build-windows.sh "$SOURCES/"
while read -r pkg; do
    curl -sSfL -o "$SOURCES/msys2/$pkg.src.tar.zst" "https://repo.msys2.org/mingw/sources/$pkg.src.tar.zst"
done < "$ROOT/msys2-sources.txt"
tar -cf "dist/ReVideo-$VERSION-windows-sources.tar" -C "$ROOT/sources" "ReVideo-$VERSION-windows-sources"

makensis -V2 -DVERSION="$VERSION" -DSTAGE="$(cygpath -w "$STAGE")" \
    -DOUTFILE="$(cygpath -w "$PWD/dist/ReVideo-$VERSION-setup.exe")" packaging/windows/installer.nsi
ls -lh dist/
