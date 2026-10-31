#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QtQmlIntegration>
#include <memory>

struct mpv_handle;

/// Audio-only mpv for one music track under the clips. It has no clock of its own:
/// sync() makes it follow the video, switching files as the pieces of the track change.
class MusicPlayer : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)

public:
    explicit MusicPlayer(QObject *parent = nullptr);
    ~MusicPlayer() override;

    double volume() const { return m_volume; }
    void setVolume(double volume);

    /// Plays `path` from `sec` while `playing`; an empty path or `playing` false pauses.
    /// Opens or seeks only when needed, so calling this on every frame is fine.
    Q_INVOKABLE void sync(const QString &path, double sec, bool playing);

signals:
    void volumeChanged();

private:
    void processEvents();
    void setPaused(bool paused);

    std::shared_ptr<mpv_handle> m_mpv;
    QString m_path;
    bool m_paused = true;
    double m_position = 0;
    double m_duration = 0;
    double m_volume = 1;
    /// A seek takes a moment to show in the position; no new one meanwhile.
    QElapsedTimer m_sinceSeek;
};
