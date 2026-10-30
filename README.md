# ReVideo

Schlanker Video-Player und Trimmer für Linux und Windows, geschrieben in C++ mit
Qt 6 / QML. Die Wiedergabe läuft über [libmpv](https://mpv.io), Vorschaubilder,
Frame-Export und Schnitt über ffmpeg.

- Spielt MP4, MKV, MOV, AVI, WebM, FLV, WMV, MPEG-TS, 3GP … direkt ab (H.264, HEVC, VP9, AV1), mit Hardware-Dekodierung
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
sudo pacman -S --needed base-devel cmake ninja pkgconf qt6-base qt6-declarative mpv ffmpeg
```

Debian / Ubuntu (ab 24.04):

```sh
sudo apt install build-essential cmake ninja-build pkg-config qt6-base-dev qt6-declarative-dev \
    qml6-module-qtquick-controls qml6-module-qtquick-dialogs qml6-module-qtquick-shapes \
    qml6-module-qtquick-effects libmpv-dev ffmpeg
```

Der Datei-Dialog nutzt unter KDE/GNOME den Dialog des Desktops (bzw. xdg-desktop-portal).

### Bauen und starten

```sh
cmake -S . -B build/linux -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/linux
build/linux/revideo ~/Videos/clip.mkv
```

### Live-Vorschau

Speichern → neu bauen → App startet neu (braucht [watchexec](https://github.com/watchexec/watchexec)):

```sh
watchexec -r -e cpp,h,qml,txt -w src -w CMakeLists.txt -- \
    'cmake --build build/linux && build/linux/revideo ~/Videos/clip.mkv'
```

Das QML ist in die Programmdatei eingebettet, auch reine QML-Änderungen brauchen
deshalb einen (kurzen) Build. Ohne Videopfad startet die App leer.

### Tests

```sh
ctest --test-dir build/linux --output-on-failure
```

Der Exporttest läuft nur, wenn `ffmpeg` mit libx264 im `PATH` liegt, sonst wird er übersprungen.

## Release

Der Code liegt privat in `Lussuv/ReVideo`. Die fertigen Pakete kommen in das öffentliche
[Lussuv/ReVideo-releases](https://github.com/Lussuv/ReVideo-releases), dort fragt die App beim Start nach.

Version in `CMakeLists.txt` (`project(ReVideo VERSION …)`) und
`packaging/linux/de.retrydev.ReVideo.metainfo.xml` erhöhen, committen, auf `main` pushen.
GitHub Actions ([release.yml](.github/workflows/release.yml)) baut dann Flatpak und
Installer und legt das Release `v<version>` in `ReVideo-releases` an.

Ist ein Lauf gescheitert, lässt er sich unter Actions → Release → „Run workflow“ neu starten.
Gebaut wird nur bei neuer Major- oder Minor-Version (`3.4.0`, `4.0.0`). Patch-Versionen
(`3.4.1`) und schon veröffentlichte Versionen überspringt der Workflow. Voraussetzung ist
das Secret `RELEASES_TOKEN` im Code-Repo: ein Fine-grained Token nur für `ReVideo-releases`
mit „Contents: Read and write“.

**Flatpak:** Runtime `org.kde.Platform//6.11` (Qt und die ffmpeg-Bibliotheken samt
`codecs-extra`). libass, libplacebo und mpv werden ins Flatpak gebaut, dazu eine
eigenständige ffmpeg mit x264 und dav1d für den Export.

**Windows:** läuft in MSYS2 (UCRT64) auf einem Windows-Runner.
[scripts/build-windows-deps.sh](scripts/build-windows-deps.sh) baut ffmpeg und mpv als
LGPL-DLLs und die Export-`ffmpeg.exe` separat (in der CI gecacht);
[scripts/build-windows.sh](scripts/build-windows.sh) baut die App, holt Qt per
`windeployqt6` und die übrigen DLLs, Lizenzen und Quellpakete per
[scripts/stage-windows.py](scripts/stage-windows.py). Der Installer arbeitet pro Benutzer
ohne Admin-Rechte und trägt ReVideo unter „Öffnen mit“ ein.

**Updates:** Windows lädt den Installer, prüft ihn gegen die SHA-256, die GitHub beim
Hochladen berechnet, installiert still und startet neu. Das Flatpak lädt das Bundle,
prüft es ebenso und installiert es über `flatpak-spawn --host flatpak install`.

## Lizenzen der Fremdkomponenten

ReVideo selbst ist proprietär. Die mitgelieferten Bibliotheken behalten ihre Lizenzen:

- **Qt** (LGPL-3.0), **libmpv** (LGPL, gebaut mit `-Dgpl=false`) und **ffmpeg** für die
  App (LGPL, ohne `--enable-gpl`) werden dynamisch gelinkt und sind austauschbar.
- Die **Export-ffmpeg** enthält x264 und ist GPL. Sie ist ein eigenständiges Programm,
  das ReVideo nur als Prozess aufruft.
- Jedes Release enthält `ReVideo-<version>-linux-sources.tar` und
  `ReVideo-<version>-windows-sources.tar` mit dem Quellcode genau dieser Komponenten;
  unter Windows liegen die Lizenztexte in `licenses/` im Installationsordner.

Ohne GPL-Teile fehlt mpv die eigene X11-Unterstützung. Für die Darstellung in Qt ist sie
nicht nötig; unter X11 entfällt nur die direkte VA-API-Hardware-Dekodierung.

## Aufbau

```
src/main.cpp            Einstieg, OpenGL, Schriften
src/mpvitem.*           Video-Fläche über die libmpv-Render-API, Wiedergabe-Zustand
src/util.*              Hilfsfunktionen und gespeicherte Einstellungen für QML
src/exporter.*          Export, Frame speichern (ffmpeg-Prozesse mit Fortschritt)
src/thumbnailer.*       Vorschaubilder für die Timeline
src/updater.*           Update-Prüfung und -Installation über GitHub-Releases
src/format.*, files.*,
src/settings.*, exportjob.*,
src/version.*           Logik ohne QML (mit Tests in tests/)
src/qml/                Oberfläche (Main.qml: Zustand und Abläufe)
packaging/              Flatpak-Manifest, Desktop-Datei, NSIS-Skript
scripts/                Windows-Build für GitHub Actions
assets/                 Icons, Schriften (Inter, JetBrains Mono — OFL)
```
