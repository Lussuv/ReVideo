#pragma once

#include <QString>

/// Kept between runs in `settings.json` under the user's config directory;
/// same file and format as the earlier Rust versions.
struct Settings {
    double volume = 0.8;
    bool muted = false;
};

/// %APPDATA%\ReVideo on Windows, $XDG_CONFIG_HOME/revideo elsewhere
/// (inside Flatpak that points into ~/.var/app).
QString settingsFile();
/// Missing or unreadable file counts as defaults.
Settings loadSettings(const QString &file = settingsFile());
void saveSettings(const Settings &settings, const QString &file = settingsFile());
