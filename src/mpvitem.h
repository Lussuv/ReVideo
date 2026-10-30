#pragma once

#include <QColor>
#include <QQuickFramebufferObject>
#include <QtQmlIntegration>
#include <memory>

struct mpv_handle;

/// Video surface backed by libmpv's OpenGL render API. One instance lives for
/// the whole session; switching videos reuses it instead of rebuilding a pipeline.
class MpvItem : public QQuickFramebufferObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool eof READ eof NOTIFY eofChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(QColor background READ background WRITE setBackground NOTIFY backgroundChanged)

    // Details of the open file, valid from fileLoaded() on.
    Q_PROPERTY(QString path READ path NOTIFY infoChanged)
    Q_PROPERTY(double duration READ duration NOTIFY infoChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY infoChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY infoChanged)
    Q_PROPERTY(double fps READ fps NOTIFY infoChanged)
    Q_PROPERTY(QString codec READ codec NOTIFY infoChanged)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY infoChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    Renderer *createRenderer() const override;

    bool loaded() const { return m_loaded; }
    double position() const { return m_position; }
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    bool eof() const { return m_eof; }
    double volume() const { return m_volume; }
    void setVolume(double volume);
    bool muted() const { return m_muted; }
    void setMuted(bool muted);
    QColor background() const { return m_background; }
    void setBackground(const QColor &color);

    QString path() const { return m_path; }
    double duration() const { return m_duration; }
    int videoWidth() const { return m_width; }
    int videoHeight() const { return m_height; }
    double fps() const { return m_fps; }
    QString codec() const { return m_codec; }
    bool hasAudio() const { return m_hasAudio; }

    /// Opens `path` and starts playback.
    Q_INVOKABLE void load(const QString &path);
    /// Closes the file; closed() follows once mpv has released it.
    Q_INVOKABLE void unload();
    /// Frame-exact seek. mpv coalesces seeks that pile up while dragging.
    Q_INVOKABLE void seek(double sec);
    /// Loops playback in [a, b); negative values turn the loop off.
    Q_INVOKABLE void setLoop(double a, double b);

signals:
    void loadedChanged();
    void positionChanged();
    void pausedChanged();
    void eofChanged();
    void volumeChanged();
    void mutedChanged();
    void backgroundChanged();
    void infoChanged();
    void fileLoaded();
    void loadFailed(const QString &error);
    void closed();
    /// The file has audio, but no audio device could be opened.
    void noAudioOutput();

private:
    Q_INVOKABLE void renderReady();
    void processEvents();
    /// False if the file has no video track.
    bool readInfo();

    std::shared_ptr<mpv_handle> m_mpv;
    bool m_loaded = false;
    double m_position = 0;
    bool m_paused = false;
    bool m_eof = false;
    double m_volume = 0.8;
    bool m_muted = false;
    QColor m_background;
    bool m_checkAudio = false;
    bool m_renderReady = false;

    QString m_path;
    double m_duration = 0;
    int m_width = 0;
    int m_height = 0;
    double m_fps = 0;
    QString m_codec;
    bool m_hasAudio = false;
};
