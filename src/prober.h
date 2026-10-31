#pragma once

#include <QObject>
#include <QVariantMap>
#include <QtQmlIntegration>

/// Reads duration, stream parameters and a thumbnail of clips that are not open in
/// the player, for the clip strip; also the duration of music.
class Prober : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    using QObject::QObject;

    Q_INVOKABLE void probe(const QString &path);

signals:
    /// `info` holds duration, hasVideo, width, height, fps, hasAudio, signature and thumb (a
    /// file URL, empty if extraction failed); without video `peaks` (20 per second, 0..1)
    /// instead of thumb. It is empty if the file has no readable stream.
    void probed(const QString &path, const QVariantMap &info);
};
