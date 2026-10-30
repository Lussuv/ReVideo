# ReVideo

Schlanker Video-Player und Trimmer für Linux und Windows, geschrieben in Rust mit
[iced](https://iced.rs). Die Wiedergabe läuft über GStreamer, Info, Thumbnails,
Frame-Export und Schnitt über ffmpeg.

- Spielt MP4, MKV, MOV, AVI, WebM, FLV, WMV, MPEG-TS, 3GP … direkt ab (H.264, HEVC, VP9, AV1)
- Trim-Timeline mit Thumbnails, Griffen und exakter Zeiteingabe
- Export **Original** (verlustfreier Stream-Copy) oder **Discord** (2-Pass H.264, ≤ 10 MB, 1080p, 30 fps)
- Aktuellen Frame als PNG speichern, Vor/Zurück im Ordner, Löschen in den Papierkorb
- Tasten: `Leertaste` Play/Pause · `←`/`→` ±5 s · `,`/`.` Frame zurück/vor · `Entf` löschen · `F11` Vollbild

Ausgeliefert wird als **Flatpak** (Linux) und als **NSIS-Installer** (Windows). Gebaut
wird beides auf GitHub, lokal läuft nur die Entwicklung.

## Entwicklung

### Pakete

Arch / CachyOS:

```sh
sudo pacman -S --needed base-devel rustup pkgconf watchexec \
    gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg
```

Debian / Ubuntu:

```sh
sudo apt install build-essential curl pkg-config \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav ffmpeg \
    libxkbcommon-dev libwayland-dev
curl https://sh.rustup.rs -sSf | sh
cargo install --locked watchexec-cli
```

Die Rust-Version steht in `rust-toolchain.toml`, rustup holt sie beim ersten `cargo`-Aufruf.
Der Datei-Dialog läuft über xdg-desktop-portal. KDE und GNOME bringen es mit, auf
anderen Desktops `xdg-desktop-portal` plus ein Backend (`-gtk` oder `-kde`) installieren.

### Live-Vorschau

Speichern → neu bauen → App startet neu (ca. 5 s):

```sh
watchexec -r -e rs,toml -w src -w Cargo.toml -- cargo run
```

Mit einem Video zum Testen: `… -- cargo run -- ~/Videos/clip.mkv`

### Tests

```sh
cargo test
```

```sh
cargo test -- --include-ignored   # zusätzlich ein echter Export mit ffmpeg, beide Vorlagen
```

## Release

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

**Flatpak:** Runtime `org.freedesktop.Platform//25.08`. ffmpeg, x264 und dav1d werden ins
Flatpak gebaut, GStreamer samt Codecs kommt aus der Runtime.

**Windows:** `scripts/fetch-windows-deps.py` lädt GStreamer und ffmpeg aus dem
MSYS2-Repository (`ucrt64`). Danach wird mit `x86_64-pc-windows-gnu` cross-kompiliert,
und `scripts/stage-windows.py` kopiert nur die tatsächlich importierten DLLs in den
Installer. Der Installer arbeitet pro Benutzer ohne Admin-Rechte und trägt ReVideo unter
„Öffnen mit“ ein.

**Updates:** Windows lädt den Installer, prüft ihn gegen die SHA-256, die GitHub beim
Hochladen berechnet, installiert still und startet neu. Unter Linux öffnet der
Update-Knopf die Release-Seite.

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
scripts/          Windows-Build für GitHub Actions
assets/           Icons, Schriften (Inter, JetBrains Mono — OFL)
```
