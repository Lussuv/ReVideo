#pragma once

#include <QObject>
#include <QStringList>
#include <QtQmlIntegration>

class QProcess;

/// Extracts evenly spaced thumbnails with ffmpeg, cached per file and
/// modification time: one run for all slots via keyframes, a second, slower
/// one only for the slots that yielded nothing.
class Thumbnailer : public QObject {
    Q_OBJECT
    QML_ELEMENT

    /// One file URL per slot in timeline order; empty for slots without an image (yet).
    Q_PROPERTY(QStringList thumbnails READ thumbnails NOTIFY thumbnailsChanged)

public:
    using QObject::QObject;

    QStringList thumbnails() const { return m_thumbs; }

    Q_INVOKABLE void start(const QString &path, double duration, int count);
    /// Kills a running ffmpeg right away; paging through a folder would
    /// otherwise leave one running per visited file.
    Q_INVOKABLE void cancel();

signals:
    void thumbnailsChanged();

private:
    QString target(int slot) const;
    void run(bool fast);
    void publish();

    QString m_path;
    QString m_dir;
    double m_duration = 0;
    int m_count = 0;
    QProcess *m_proc = nullptr;
    QStringList m_thumbs;
};
