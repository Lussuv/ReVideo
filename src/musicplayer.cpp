#include "musicplayer.h"

#include <cmath>
#include <initializer_list>
#include <mpv/client.h>

namespace {
enum Observed : uint64_t { TimePos = 1, Duration };
/// Larger gaps between music and video are corrected by a seek.
constexpr double MAX_DRIFT = 0.15;
} // namespace

MusicPlayer::MusicPlayer(QObject *parent)
    : QObject(parent), m_mpv(mpv_create(), mpv_terminate_destroy)
{
    if (!m_mpv)
        qFatal("mpv konnte nicht gestartet werden");
    mpv_handle *mpv = m_mpv.get();
    for (const auto &[key, value] : std::initializer_list<std::pair<const char *, const char *>>{
             {"vid", "no"},
             {"vo", "null"},
             {"keep-open", "yes"},
             {"idle", "yes"},
             {"pause", "yes"},
             {"hr-seek", "yes"},
             {"input-default-bindings", "no"},
             {"audio-display", "no"},
             {"load-scripts", "no"},
             {"ytdl", "no"},
         })
        mpv_set_option_string(mpv, key, value);
    if (mpv_initialize(mpv) < 0)
        qFatal("mpv konnte nicht initialisiert werden");
    mpv_request_log_messages(mpv, "error");
    mpv_observe_property(mpv, TimePos, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(mpv, Duration, "duration", MPV_FORMAT_DOUBLE);
    mpv_set_wakeup_callback(
        mpv,
        [](void *self) {
            auto *player = static_cast<MusicPlayer *>(self);
            QMetaObject::invokeMethod(player, [player] { player->processEvents(); }, Qt::QueuedConnection);
        },
        this);
}

MusicPlayer::~MusicPlayer()
{
    mpv_set_wakeup_callback(m_mpv.get(), nullptr, nullptr);
}

void MusicPlayer::setVolume(double volume)
{
    if (m_volume == volume)
        return;
    double percent = volume * 100;
    mpv_set_property_async(m_mpv.get(), 0, "volume", MPV_FORMAT_DOUBLE, &percent);
    m_volume = volume;
    emit volumeChanged();
}

void MusicPlayer::sync(const QString &path, double sec, bool playing)
{
    if (path.isEmpty() || !playing || sec < 0 || (path == m_path && m_duration > 0 && sec >= m_duration)) {
        setPaused(true);
        return;
    }
    const QByteArray target = QByteArray::number(sec, 'f', 3);
    if (path != m_path) {
        // Opening right at the position saves a seek.
        m_path = path;
        m_duration = 0;
        mpv_set_property_string(m_mpv.get(), "start", target.constData());
        const QByteArray file = path.toUtf8();
        const char *cmd[] = {"loadfile", file.constData(), nullptr};
        mpv_command_async(m_mpv.get(), 0, cmd);
        m_position = sec;
        m_sinceSeek.start();
    } else if ((!m_sinceSeek.isValid() || m_sinceSeek.elapsed() > 300) && std::abs(m_position - sec) > MAX_DRIFT) {
        const char *cmd[] = {"seek", target.constData(), "absolute+exact", nullptr};
        mpv_command_async(m_mpv.get(), 0, cmd);
        m_position = sec;
        m_sinceSeek.start();
    }
    setPaused(false);
}

void MusicPlayer::setPaused(bool paused)
{
    if (m_paused == paused)
        return;
    m_paused = paused;
    int flag = paused;
    mpv_set_property_async(m_mpv.get(), 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void MusicPlayer::processEvents()
{
    mpv_handle *mpv = m_mpv.get();
    while (true) {
        mpv_event *ev = mpv_wait_event(mpv, 0);
        if (ev->event_id == MPV_EVENT_NONE)
            return;
        if (ev->event_id == MPV_EVENT_LOG_MESSAGE) {
            const auto *msg = static_cast<mpv_event_log_message *>(ev->data);
            qWarning("mpv-musik/%s: %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
        } else if (ev->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            const auto *p = static_cast<mpv_event_property *>(ev->data);
            if (p->format != MPV_FORMAT_DOUBLE)
                continue;
            const double v = *static_cast<double *>(p->data);
            if (ev->reply_userdata == TimePos)
                m_position = v;
            else if (ev->reply_userdata == Duration)
                m_duration = v;
        }
    }
}
