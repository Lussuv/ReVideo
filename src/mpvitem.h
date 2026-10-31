#pragma once

#include <QColor>
#include <QElapsedTimer>
#include <QQuickFramebufferObject>
#include <QVariantList>
#include <QtQmlIntegration>
#include <memory>

struct mpv_handle;

/// Video surface backed by libmpv's OpenGL render API. One instance lives for
/// the whole session; switching videos reuses it instead of rebuilding a pipeline.
/// It holds two mpv players: a sequence plays on one while the other waits on the
/// first frame of the next clip, so that changing clips is just switching over.
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
    /// Entry of loadSequence() that is playing; 0 for a single file.
    Q_PROPERTY(int playlistPos READ playlistPos NOTIFY playlistPosChanged)

    // Details of the open file, valid from fileLoaded() on.
    Q_PROPERTY(QString path READ path NOTIFY infoChanged)
    Q_PROPERTY(double duration READ duration NOTIFY infoChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY infoChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY infoChanged)
    Q_PROPERTY(double fps READ fps NOTIFY infoChanged)
    Q_PROPERTY(QString codec READ codec NOTIFY infoChanged)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY infoChanged)
    /// False for music; its cover is not shown.
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY infoChanged)
    /// From the tags; the title falls back to the file name.
    Q_PROPERTY(QString title READ title NOTIFY infoChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY infoChanged)

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
    int playlistPos() const { return m_playlistPos; }
    void setBackground(const QColor &color);

    QString path() const { return m_path; }
    double duration() const { return m_duration; }
    int videoWidth() const { return m_width; }
    int videoHeight() const { return m_height; }
    double fps() const { return m_fps; }
    QString codec() const { return m_codec; }
    bool hasAudio() const { return m_hasAudio; }
    bool hasVideo() const { return m_hasVideo; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }

    /// Player whose picture is shown; the renderer takes it over in synchronize().
    int activePlayer() const { return m_active; }

    /// Opens `path` at `start` seconds and starts playback.
    Q_INVOKABLE void load(const QString &path, double start = 0);
    /// Plays `entries` (maps with path, start, end, muted) back to back, keeping the
    /// paused state. fileLoaded() follows for every entry.
    Q_INVOKABLE void loadSequence(const QVariantList &entries);
    /// Drops the file's audio track (a muted clip), apart from the user's mute.
    Q_INVOKABLE void setAudioOff(bool off);
    /// Jumps to entry `index` of the sequence, at its start.
    Q_INVOKABLE void playIndex(int index);
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
    void playlistPosChanged();
    void infoChanged();
    void fileLoaded();
    void loadFailed(const QString &error);
    void closed();
    /// The file has audio, but no audio device could be opened.
    void noAudioOutput();

private:
    Q_INVOKABLE void renderReady();
    void processEvents(int player);
    /// False if the file has neither video nor audio.
    bool readInfo(int player);
    mpv_handle *handle(int player) const { return m_mpv[player].get(); }
    /// Opens sequence entry `entry` on `player`, paused or not.
    void loadEntry(int player, int entry, bool paused);
    /// The waiting player takes over; the other one prepares the entry after it.
    void switchTo(int player);
    /// Lets the waiting player prepare `entry`, or stop if there is none.
    void prepare(int player, int entry);

    std::shared_ptr<mpv_handle> m_mpv[2];
    struct Wakeup {
        MpvItem *item;
        int player;
    } m_wakeup[2] = {{this, 0}, {this, 1}};
    int m_active = 0;

    bool m_sequence = false;
    QVariantList m_entries;
    /// Sequence entry each player holds, and whether its first frame is decoded.
    int m_entry[2] = {-1, -1};
    bool m_ready[2] = {false, false};
    /// Whether each player has loaded its entry (fileLoaded may be repeated for a seek).
    bool m_fileLoaded[2] = {false, false};
    /// Entry to switch to as soon as the waiting player is ready; -1 none.
    int m_switchTarget = -1;

    bool m_loaded = false;
    double m_position = 0;
    bool m_paused = false;
    bool m_eof = false;
    double m_volume = 0.8;
    bool m_muted = false;
    QColor m_background;
    int m_playlistPos = -1;
    bool m_checkAudio = false;
    /// From load() to the first frame, for the log.
    QElapsedTimer m_loadTimer;
    bool m_renderReady = false;

    QString m_path;
    double m_duration = 0;
    int m_width = 0;
    int m_height = 0;
    double m_fps = 0;
    QString m_codec;
    bool m_hasAudio = false;
    bool m_hasVideo = false;
    QString m_title;
    QString m_artist;
};
