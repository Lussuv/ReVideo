#!/usr/bin/env bash
# Fremdkomponenten für den Windows-Build in MSYS2 UCRT64, Ergebnis in build/windows/
# (src: Quellarchive, lgpl: ffmpeg-DLLs + libmpv, export: ffmpeg.exe). Die CI cached
# diese Verzeichnisse, siehe .github/workflows/release.yml; danach scripts/build-windows.sh.
#
# Lizenzen: ffmpeg und mpv werden hier als LGPL gebaut und als DLLs neben die App
# gelegt (austauschbar). Die Export-ffmpeg.exe enthält x264 und ist damit GPL; die
# App startet sie nur als eigenes Programm und linkt nie dagegen.
set -euo pipefail
cd "$(dirname "$0")/.."

FFMPEG=9.0.2
FFMPEG_SHA=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
MPV=0.41.0
MPV_SHA=ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209

ROOT=$PWD/build/windows
SRC=$ROOT/src
LGPL=$ROOT/lgpl
EXPORT=$ROOT/export
JOBS=$(nproc)
mkdir -p "$SRC"

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
    install -Dm644 "$ROOT/ffmpeg-lgpl/COPYING.LGPLv2.1" "$LGPL/licenses/ffmpeg/COPYING.LGPLv2.1"
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
    install -Dm644 "$ROOT/mpv-src/LICENSE.LGPL" "$LGPL/licenses/mpv/LICENSE.LGPL"
fi

# Export-ffmpeg: libav* statisch in der exe, damit sie nicht mit den LGPL-DLLs kollidiert
if [ ! -f "$EXPORT/bin/ffmpeg.exe" ]; then
    rm -rf "$ROOT/ffmpeg-gpl" && mkdir -p "$ROOT/ffmpeg-gpl"
    tar -xf "$SRC/ffmpeg-$FFMPEG.tar.xz" -C "$ROOT/ffmpeg-gpl" --strip-components=1
    (cd "$ROOT/ffmpeg-gpl" && ./configure --prefix="$EXPORT" --disable-shared --enable-static \
        --enable-gpl --enable-libx264 --enable-libdav1d --disable-ffplay --disable-ffprobe \
        --disable-doc --disable-debug \
        && make -j"$JOBS" && make install)
    install -Dm644 "$ROOT/ffmpeg-gpl/COPYING.GPLv2" "$EXPORT/licenses/ffmpeg/COPYING.GPLv2"
fi
