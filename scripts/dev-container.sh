#!/usr/bin/env bash
# Live-Test im VS-Code-Devcontainer. Startet eine eigene D-Bus-Session mit
# xdg-desktop-portal(-gtk), damit der Datei-Dialog funktioniert.
# Aufruf: scripts/dev-container.sh [VIDEO]
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- "$0" "$@"
fi

# Weitergeleitetes X-Display ohne xauth; das Fenster läuft über Wayland.
if [ -n "${WAYLAND_DISPLAY:-}" ]; then unset DISPLAY; fi

# Ohne passende portals.conf wählt xdg-desktop-portal >= 1.18 kein Backend.
conf=$PWD/build/dev-portal
mkdir -p "$conf/xdg-desktop-portal"
printf '[preferred]\ndefault=gtk\n' > "$conf/xdg-desktop-portal/portals.conf"
/usr/libexec/xdg-desktop-portal-gtk &
XDG_CONFIG_HOME=$conf /usr/libexec/xdg-desktop-portal &

exec watchexec -r -e rs,toml -w src -w Cargo.toml -- cargo run -- "$@"
