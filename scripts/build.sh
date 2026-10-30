#!/usr/bin/env bash
# Windows-Build für GitHub Actions (.github/workflows/release.yml), das Flatpak baut dort
# die flatpak-builder-Action. Aufruf: scripts/build.sh [stage|installer]
#   stage      Cross-Build + DLLs nach build/windows/stage (Arch-Container: UCRT-mingw)
#   installer  NSIS-Installer nach dist/ (Ubuntu: makensis)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)

stage() {
    local sysroot=$PWD/build/windows/sysroot
    [ -d "$sysroot/ucrt64" ] || python3 -I scripts/fetch-windows-deps.py "$sysroot"
    PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_SYSROOT_DIR="$sysroot" PKG_CONFIG_PATH= \
        PKG_CONFIG_LIBDIR="$sysroot/ucrt64/lib/pkgconfig" \
        cargo build --release --locked --target x86_64-pc-windows-gnu
    python3 -I scripts/stage-windows.py target/x86_64-pc-windows-gnu/release/revideo.exe \
        "$sysroot/ucrt64" build/windows/stage
}

installer() {
    mkdir -p dist
    makensis -V2 -DVERSION="$VERSION" -DSTAGE="$PWD/build/windows/stage" \
        -DOUTFILE="$PWD/dist/ReVideo-$VERSION-setup.exe" packaging/windows/installer.nsi
    ls -lh "dist/ReVideo-$VERSION-setup.exe"
}

case "${1:-}" in
    stage) stage ;;
    installer) installer ;;
    *) echo "Aufruf: $0 [stage|installer]" >&2; exit 1 ;;
esac
