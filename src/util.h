#pragma once

#include <QObject>
#include <QUrl>
#include <QtQmlIntegration>

/// Stateless helpers and the saved settings for QML.
class Util : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString launchFile READ launchFile CONSTANT)
    Q_PROPERTY(QStringList videoExtensions READ videoExtensions CONSTANT)
    Q_PROPERTY(double savedVolume READ savedVolume CONSTANT)
    Q_PROPERTY(bool savedMuted READ savedMuted CONSTANT)

public:
    explicit Util(QObject *parent = nullptr);

    QString launchFile() const;
    QStringList videoExtensions() const;
    double savedVolume() const { return m_volume; }
    bool savedMuted() const { return m_muted; }

    Q_INVOKABLE QString formatTime(double sec, bool withMs) const;
    /// Negative if the input is not a valid time.
    Q_INVOKABLE double parseTime(const QString &input) const;
    Q_INVOKABLE QString formatBytes(double bytes) const;
    Q_INVOKABLE QString aspectRatio(int w, int h) const;
    Q_INVOKABLE double snapToFrame(double sec, double frame) const;
    Q_INVOKABLE double tickStep(double duration, double width, double gap) const;

    /// Next/previous video in the folder; `skipSelf` also excludes `path` itself
    /// (needed after deleting it). Empty if there is none.
    Q_INVOKABLE QString adjacentVideo(const QString &path, int direction, bool skipSelf) const;
    /// Empty on success.
    Q_INVOKABLE QString moveToTrash(const QString &path) const;
    Q_INVOKABLE double fileSize(const QString &path) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString baseName(const QString &path) const;
    Q_INVOKABLE QString suffix(const QString &path) const;
    Q_INVOKABLE QUrl folderUrl(const QString &path) const;
    /// URL of `name` in the folder of `path`, e.g. a suggested export file.
    Q_INVOKABLE QUrl siblingUrl(const QString &path, const QString &name) const;
    Q_INVOKABLE QString urlToPath(const QUrl &url) const;

    Q_INVOKABLE void saveSettings(double volume, bool muted);

private:
    double m_volume;
    bool m_muted;
};
