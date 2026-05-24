# Sidecar binaries

Diesen Ordner befüllt `scripts/fetch-ffmpeg.ps1`:

- `ffmpeg-<rust-host-triple>.exe`  (z. B. `ffmpeg-x86_64-pc-windows-msvc.exe`)
- `ffprobe-<rust-host-triple>.exe`

Tauri 2 erwartet Sidecar-Binaries mit Triple-Suffix — beim Bundling werden sie
ohne Suffix in den Installer kopiert und zur Laufzeit über
`tauri_plugin_shell::ShellExt::sidecar("binaries/ffmpeg")` angesprochen.

Die `.exe`-Dateien sind in `.gitignore` ausgeschlossen, weil sie ~80 MB groß
sind. Vor dem ersten `npm run tauri dev` / `tauri build` müssen sie also
einmal lokal erzeugt werden.
