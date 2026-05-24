# App-Icons

Generiert per `powershell -ExecutionPolicy Bypass -File scripts/generate-icons.ps1`.

Tauri verlangt Icons unter folgenden Namen in diesem Ordner:

- `32x32.png`
- `128x128.png`
- `128x128@2x.png`
- `icon.ico`
- (optional, für macOS) `icon.icns`

Du kannst sie generieren lassen via:

```powershell
npm run tauri icon path\to\source.png
```

Solange noch keine Icons existieren, läuft `npm run tauri dev` zwar, aber der
Release-Build (`npm run tauri build`) bricht ab. Einfach ein 1024×1024-PNG mit
deinem Logo durch `tauri icon` schicken — der Befehl füllt diesen Ordner
automatisch.
