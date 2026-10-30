# ReVideo

Schlanker Video-Player und Trimmer für Linux und Windows, geschrieben in Rust mit
[iced](https://iced.rs). Die Wiedergabe läuft über GStreamer, Info, Thumbnails,
Frame-Export und Schnitt über ffmpeg.

- Spielt MP4, MKV, MOV, AVI, WebM, FLV, WMV, MPEG-TS, 3GP … direkt ab (H.264, HEVC, VP9, AV1)
- Trim-Timeline mit Thumbnails, Griffen und exakter Zeiteingabe
- Export **Original** (verlustfreier Stream-Copy) oder **Discord** (2-Pass H.264, ≤ 10 MB, 1080p, 30 fps)
- Aktuellen Frame als PNG speichern, Vor/Zurück im Ordner, Löschen in den Papierkorb
- Tasten: `Leertaste` Play/Pause · `←`/`→` ±5 s · `,`/`.` Frame zurück/vor · `Entf` löschen · `F11` Vollbild

Ausgeliefert wird als **Flatpak** (Linux) und als **NSIS-Installer** (Windows). Beides
wird unter Linux gebaut.

## Entwicklungsumgebung einrichten

### 1. Pakete

Arch / CachyOS:

```sh
sudo pacman -S --needed base-devel rustup pkgconf python zstd \
    gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg \
    mingw-w64-gcc flatpak flatpak-builder watchexec
paru -S nsis   # makensis — falls es nicht in den offiziellen Repos liegt, aus dem AUR
```

Debian / Ubuntu:

```sh
sudo apt install build-essential curl pkg-config python3 zstd \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav ffmpeg \
    libxkbcommon-dev libwayland-dev mingw-w64 nsis flatpak flatpak-builder
curl https://sh.rustup.rs -sSf | sh
cargo install --locked watchexec-cli
```

### 2. Rust-Toolchain

Version und Windows-Target stehen in `rust-toolchain.toml`. rustup installiert beides
beim ersten `cargo`-Aufruf im Projektordner selbst, es ist nichts weiter zu tun.

### 3. Starten und testen

Live-Test (speichern → neu bauen → App startet neu, ca. 5 s):

```sh
watchexec -r -e rs,toml -w src -w Cargo.toml -- cargo run
```

Der Datei-Dialog läuft über xdg-desktop-portal. KDE und GNOME bringen es mit, auf
anderen Desktops `xdg-desktop-portal` plus ein Backend (`-gtk` oder `-kde`) installieren.

Einmal starten, mit oder ohne Datei:

```sh
cargo run
```

```sh
cargo run -- ~/Videos/clip.mkv
```

Tests (der zweite Befehl macht zusätzlich einen echten Export mit ffmpeg, beide Vorlagen):

```sh
cargo test
```

```sh
cargo test -- --include-ignored
```

### 4. Release bauen

```sh
scripts/build.sh            # beides
scripts/build.sh linux      # nur Flatpak
scripts/build.sh windows    # nur Windows-Installer
```

Ergebnis in `dist/`:

| Datei | Inhalt |
|---|---|
| `ReVideo-<version>-x86_64.flatpak` | Flatpak-Bundle, installieren mit `flatpak install --user dist/ReVideo-*.flatpak` |
| `ReVideo-<version>-setup.exe` | Windows-Installer (pro Benutzer, ohne Admin-Rechte), trägt ReVideo unter „Öffnen mit“ ein |

Die Version steht nur in `Cargo.toml`. Build-Skript und Installer lesen sie von dort.

**Flatpak:** Beim ersten Lauf werden die Runtime `org.freedesktop.Platform//25.08` und
die Rust-SDK-Erweiterung von Flathub installiert. ffmpeg und x264 werden ins Flatpak
gebaut, GStreamer samt Codecs kommt aus der Runtime. `flatpak-builder` braucht
User-Namespaces, läuft also auf dem Host und nicht in einem unprivilegierten Container.

**Windows:** `scripts/fetch-windows-deps.py` lädt GStreamer und ffmpeg aus dem
MSYS2-Repository (`ucrt64`) nach `build/windows/sysroot`. Danach wird mit
`x86_64-pc-windows-gnu` cross-kompiliert, und `scripts/stage-windows.py` kopiert
nur die tatsächlich importierten DLLs in den Installer. Wenn du `build/windows`
löschst, holt der nächste Lauf aktuelle Pakete.

### 5. Release veröffentlichen

Der Code liegt privat in `Lussuv/ReVideo`. Die fertigen Pakete kommen in das öffentliche
[Lussuv/ReVideo-releases](https://github.com/Lussuv/ReVideo-releases), dort fragt die App beim Start nach.

Version in `Cargo.toml` und `packaging/linux/de.retrydev.ReVideo.metainfo.xml` erhöhen,
committen, auf `main` pushen. GitHub Actions ([release.yml](.github/workflows/release.yml))
baut dann Flatpak und Installer und legt das Release `v<version>` in `ReVideo-releases` an.

Gebaut wird nur bei neuer Major- oder Minor-Version (`3.1.0`, `4.0.0`). Patch-Versionen
(`3.1.1`) und schon veröffentlichte Versionen überspringt der Workflow, sie erreichen
die Nutzer erst mit der nächsten Minor-Version. Voraussetzung ist das Secret `RELEASES_TOKEN`
im Code-Repo: ein Fine-grained Token nur für `ReVideo-releases` mit
„Contents: Read and write“.

Von Hand geht es auch: `scripts/build.sh`, dann im Release-Repo ein Release mit Tag
`v<version>` anlegen und die beiden Dateien aus `dist/` anhängen.

Windows lädt den Installer, prüft ihn gegen die SHA-256, die GitHub beim Hochladen
berechnet, installiert still und startet neu. Unter Linux öffnet der Update-Knopf die
Release-Seite.

## Aufbau

```
src/main.rs       Einstieg, Fenster, Schriften
src/app.rs        Zustand, Update-Logik, Oberfläche
src/timeline.rs   Trim-Timeline (Canvas)
src/media.rs      Export, Thumbnails, Frame speichern, Ordner-Navigation, Papierkorb
src/ffmpeg.rs     ffmpeg/ffprobe-Aufrufe mit Fortschritt
src/update.rs     Update-Prüfung und -Installation über GitHub-Releases
src/theme.rs      Retry-Design-Farben und Widget-Stile
packaging/        Flatpak-Manifest, Desktop-Datei, NSIS-Skript
scripts/          Build-Skript und Windows-Helfer
assets/           Icons, Schriften (Inter, JetBrains Mono — OFL)
```
