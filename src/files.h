#pragma once

#include <QSet>
#include <QString>
#include <QStringList>

class QProcess;

const QStringList &videoExtensions();
bool isVideoFile(const QString &path);
/// First video file passed on the command line (file association / "Open with").
QString launchFile(const QStringList &args);
/// Next/previous video in the same folder (alphabetical, wrapping), skipping
/// `excluded` (canonical paths). Empty if there is none.
QString adjacentVideo(const QString &current, int direction, const QSet<QString> &excluded);
QString canonical(const QString &path);
/// Empty on success, otherwise a message for the user.
QString moveToTrash(const QString &path);
bool inFlatpak();

/// Bundled tool next to the executable (Windows installer, Flatpak /app/bin),
/// otherwise the name for a PATH lookup.
QString toolPath(const QString &name);
/// Keeps console tools from opening a console window on Windows.
void prepareTool(QProcess &proc);
/// Short stable hex id, e.g. for cache directory names.
QString shortHash(const QString &text);
/// Writable directory under the OS temp for thumbnails, pass logs and updates.
QString tempSubdir(const QString &name);
