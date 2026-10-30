#pragma once

#include <QObject>
#include <QStringList>
#include <QtQmlIntegration>

class QProcess;

/// Extracts evenly spaced thumbnails with ffmpeg, one after another, cached
/// per file and modification time.
class Thumbnailer : public QObject {
    Q_OBJECT
    QML_ELEMENT

    /// File URLs in timeline order; grows while the job runs.
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
    void next();
    void extract(const QString &target, double ts, bool fast);

    QString m_path;
    QString m_dir;
    double m_duration = 0;
    int m_count = 0;
    int m_index = 0;
    QProcess *m_proc = nullptr;
    QStringList m_thumbs;
};
