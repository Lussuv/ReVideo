# Retry Player (ReVideo)

Schlanker, dunkler Video-Player & Trimmer für Windows — Tauri 2 + Rust + React.

## Features (Grundaufbau)
- Öffnen beliebiger Videoformate (MP4, MKV, MOV, AVI, WebM, FLV, WMV, …)
- Play / Pause, −5s / +5s, vorheriger / nächster Frame
- Lautstärke-Slider, Mute, Fullscreen
- Trim-Timeline mit zwei Drag-Handles, Thumbnail-Strip, präzise Start/End-Inputs
- Export in MP4 (H.264 / H.265), WebM (VP9), MOV (ProRes), GIF
- FFmpeg läuft als Sidecar — kein System-FFmpeg nötig

## Erstmaliges Setup

### 1) Toolchain installieren
- **Rust**: https://rustup.rs (rustup-init.exe ausführen)
- **Node.js**: https://nodejs.org (LTS reicht; bringt npm mit)
- **Visual Studio Build Tools** (für Tauri unter Windows): "C++ build tools" Workload installieren

### 2) Repo-Dependencies
```powershell
npm install
```

### 3) FFmpeg-Sidecar holen
```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-ffmpeg.ps1
```

### 3b) App-Icons generieren (einmalig)
```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate-icons.ps1
```
Erzeugt das Lila-Hexagon-Logo unter `src-tauri/icons/` in allen von Tauri
benötigten Größen + Multi-Res-ICO. Eigenes Logo? Einfach ein 1024×1024-PNG
mit `npm run tauri icon <pfad>` schicken — überschreibt diese.
Lädt die gyan.dev-Essentials-Builds und legt sie unter
`src-tauri/binaries/ffmpeg-<triple>.exe` / `ffprobe-<triple>.exe` ab.
Die Binaries sind in `.gitignore` ausgeschlossen.

### 4) Starten
```powershell
npm run tauri dev
```

### 5) Release-Build
```powershell
npm run tauri build
```
Erzeugt MSI- und NSIS-Installer unter `src-tauri/target/release/bundle/`.

## Tastatur-Shortcuts
| Taste | Aktion |
|------|--------|
| `Space` | Play / Pause |
| `←` / `→` | −5s / +5s |
| `,` / `.` | Vorheriger / nächster Frame |

## Struktur
```
src/                     React + TS UI
  components/            TopBar, VideoStage, TrimTimeline, Sidebar-Cards, EmptyState, Icons
  hooks/usePlayer.ts     <video>-State-Bindings
  lib/                   Tauri-Bridge & Formatter
src-tauri/               Tauri/Rust Backend
  src/commands.rs        get_video_info, export_clip, generate_thumbnails
  src/ffmpeg.rs          Sidecar-Wrapper (ffmpeg + ffprobe)
  binaries/              ffmpeg-<triple>.exe (per Script geholt, nicht im Repo)
scripts/fetch-ffmpeg.ps1 FFmpeg-Download-Helper
```

## Ideen für die nächste Iteration
- Drag & Drop ins Fenster
- Recents-Liste (zuletzt geöffnete Dateien)
- Audio-Wellenform unter der Trim-Timeline
- Speed-Control (0.25× … 4×)
- Mehrfach-Cut (mehr als ein Trim-Range pro Export)
- Pixel-genauer Step über `ffmpeg -filter_complex select=` statt fps-Schätzung
- Proxy-Pipeline für riesige 4K-Dateien (vorab in kleine MP4-Preview transcoden)
