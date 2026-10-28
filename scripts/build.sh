#!/usr/bin/env bash
# Baut ReVideo als Flatpak (Linux) und als NSIS-Installer (Windows, cross-kompiliert).
# Aufruf: scripts/build.sh [linux|windows|all]   — Ergebnis liegt in dist/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
APP_ID=de.retrydev.ReVideo
mkdir -p dist

build_linux() {
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak-builder --user --force-clean --install-deps-from=flathub \
        --repo=build/flatpak-repo build/flatpak "packaging/linux/$APP_ID.yml"
    flatpak build-bundle build/flatpak-repo "dist/ReVideo-$VERSION-x86_64.flatpak" "$APP_ID" \
        --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
}

build_windows() {
    local sysroot=$PWD/build/windows/sysroot
    # Löschen von build/windows holt beim nächsten Lauf aktuelle MSYS2-Pakete.
    [ -d "$sysroot/ucrt64" ] || python3 -I scripts/fetch-windows-deps.py "$sysroot"
    PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_SYSROOT_DIR="$sysroot" PKG_CONFIG_PATH= \
        PKG_CONFIG_LIBDIR="$sysroot/ucrt64/lib/pkgconfig" \
        cargo build --release --target x86_64-pc-windows-gnu
    python3 -I scripts/stage-windows.py target/x86_64-pc-windows-gnu/release/revideo.exe \
        "$sysroot/ucrt64" build/windows/stage
    makensis -V2 -DVERSION="$VERSION" -DSTAGE="$PWD/build/windows/stage" \
        -DOUTFILE="$PWD/dist/ReVideo-$VERSION-setup.exe" packaging/windows/installer.nsi
}

case "${1:-all}" in
    linux) build_linux ;;
    windows) build_windows ;;
    all) build_linux; build_windows ;;
    *) echo "Aufruf: $0 [linux|windows|all]" >&2; exit 1 ;;
esac
ls -lh dist/
