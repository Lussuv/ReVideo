#!/usr/bin/env bash
# Live-Test im VS-Code-Devcontainer. Startet eine eigene D-Bus-Session mit
# xdg-desktop-portal(-gtk), damit der Datei-Dialog funktioniert.
# Aufruf: scripts/dev-container.sh [VIDEO]
set -euo pipefail
cd "$(dirname "$0")/.."

dir=$PWD/build/dev-portal
log=$dir/session.log
mkdir -p "$dir/xdg-desktop-portal"
: > "$log"

# Weitergeleitetes X-Display ohne xauth; das Fenster läuft über Wayland.
if [ -n "${WAYLAND_DISPLAY:-}" ]; then unset DISPLAY; fi

# Bus und alle darüber gestarteten Dienste schreiben ins Log statt ins Terminal.
mapfile -t bus < <(dbus-daemon --session --fork --print-address=1 --print-pid=1 2>>"$log")
export DBUS_SESSION_BUS_ADDRESS=${bus[0]}
trap 'kill "${bus[1]}" 2>/dev/null' EXIT

# Ohne passende portals.conf wählt xdg-desktop-portal >= 1.18 kein Backend.
printf '[preferred]\ndefault=gtk\n' > "$dir/xdg-desktop-portal/portals.conf"
XDG_CONFIG_HOME=$dir /usr/libexec/xdg-desktop-portal 2>>"$log" &

echo "Portal-Log: $log"
watchexec -r -e rs,toml -w src -w Cargo.toml -- cargo run -- "$@"
