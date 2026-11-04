# ReVideo

Schlanker Video-Player und Trimmer für Linux und Windows, geschrieben in C++ mit
Qt 6 / QML. Die Wiedergabe läuft über [libmpv](https://mpv.io), Vorschaubilder,
Frame-Export und Schnitt über [ffmpeg](https://ffmpeg.org).

- Spielt MP4, MKV, MOV, AVI, WebM, FLV, WMV, MPEG-TS, 3GP … direkt ab (H.264, HEVC, VP9, AV1), mit Hardware-Dekodierung
- Trim-Timeline mit Thumbnails, Griffen und exakter Zeiteingabe
- Export **Original** (verlustfreier Stream-Copy) oder **Discord** (H.264, ≤ 10 MB, 1080p, 30 fps)
- Aktuellen Frame als PNG speichern, Vor/Zurück im Ordner, Löschen in den Papierkorb
- Tasten: `Leertaste` Play/Pause · `←`/`→` ±5 s · `,`/`.` Frame zurück/vor · `Entf` löschen · `F11` Vollbild

## Download

Die aktuelle Version gibt es unter
[Releases](https://github.com/Lussuv/ReVideo-releases/releases/latest):

- **Windows:** `ReVideo-<version>-setup.exe`. Installiert pro Benutzer, ohne Admin-Rechte.
- **Linux:** `ReVideo-<version>-x86_64.flatpak`, Installation mit
  `flatpak install --user ReVideo-<version>-x86_64.flatpak`

Die App sucht beim Start nach Updates und installiert sie auf Wunsch.

## Selbst bauen (Linux)

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

Bauen, testen, starten:

```sh
cmake -S . -B build/linux -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/linux
ctest --test-dir build/linux --output-on-failure
build/linux/revideo ~/Videos/clip.mkv
```

Die offiziellen Pakete baut GitHub Actions ([release.yml](.github/workflows/release.yml)),
den Windows-Build in MSYS2 mit [scripts/build-windows.sh](scripts/build-windows.sh).

## Lizenz

ReVideo steht unter der [GNU General Public License v3.0 oder später](LICENSE).

Die mitgelieferten Komponenten behalten ihre eigenen Lizenzen: Qt, libmpv und ffmpeg
(LGPL, dynamisch gelinkt) sowie eine eigenständige `ffmpeg` mit x264 (GPL) für den Export.
Jedes Release enthält den Quellcode genau dieser Komponenten
(`ReVideo-<version>-*-sources.tar`). Die Schriften Inter und JetBrains Mono stehen unter
der SIL Open Font License.
