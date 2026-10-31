#include "mpvitem.h"

#include <QGuiApplication>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QtGui/qguiapplication_platform.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>

namespace {

enum Observed : uint64_t { TimePos = 1, Pause, EofReached };

void *getProcAddress(void *, const char *name)
{
    QOpenGLContext *ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void *>(ctx->getProcAddress(name)) : nullptr;
}

class MpvRenderer : public QQuickFramebufferObject::Renderer {
public:
    MpvRenderer(std::shared_ptr<mpv_handle> first, std::shared_ptr<mpv_handle> second, MpvItem *item)
        : m_mpv{std::move(first), std::move(second)}, m_item(item)
    {
    }

    // Runs on the render thread; must happen before the mpv handles go away,
    // which the shared handles guarantee.
    ~MpvRenderer() override
    {
        for (mpv_render_context *ctx : m_ctx)
            if (ctx)
                mpv_render_context_free(ctx);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_ctx[0])
            init();
        return new QOpenGLFramebufferObject(size);
    }

    void synchronize(QQuickFramebufferObject *item) override
    {
        m_active = static_cast<MpvItem *>(item)->activePlayer();
    }

    void render() override
    {
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo target{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flip = 0;
        for (int p = 0; p < 2; ++p) {
            if (!m_ctx[p])
                continue;
            // The waiting player's frames are only acknowledged, so that it does not stall.
            int skip = p != m_active;
            if (skip && !(mpv_render_context_update(m_ctx[p]) & MPV_RENDER_UPDATE_FRAME))
                continue;
            mpv_render_param params[] = {{MPV_RENDER_PARAM_OPENGL_FBO, &target},
                                         {MPV_RENDER_PARAM_FLIP_Y, &flip},
                                         {MPV_RENDER_PARAM_SKIP_RENDERING, &skip},
                                         {MPV_RENDER_PARAM_INVALID, nullptr}};
            mpv_render_context_render(m_ctx[p], params);
        }
    }

private:
    void init()
    {
        mpv_opengl_init_params gl{getProcAddress, nullptr};
        QList<mpv_render_param> params = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl},
        };
        // Hardware decoding interop (VA-API) needs the native display.
#ifdef Q_OS_LINUX
#if QT_CONFIG(wayland)
        if (auto *wl = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
            params.append({MPV_RENDER_PARAM_WL_DISPLAY, wl->display()});
#endif
#if QT_CONFIG(xcb)
        if (auto *x11 = qGuiApp->nativeInterface<QNativeInterface::QX11Application>())
            params.append({MPV_RENDER_PARAM_X11_DISPLAY, x11->display()});
#endif
#endif
        params.append({MPV_RENDER_PARAM_INVALID, nullptr});
        for (int p = 0; p < 2; ++p) {
            if (mpv_render_context_create(&m_ctx[p], m_mpv[p].get(), params.data()) < 0) {
                qWarning("mpv: Render-Kontext konnte nicht erstellt werden");
                m_ctx[p] = nullptr;
                return;
            }
            mpv_render_context_set_update_callback(
                m_ctx[p],
                [](void *item) {
                    QMetaObject::invokeMethod(static_cast<MpvItem *>(item), "update", Qt::QueuedConnection);
                },
                m_item);
        }
        QMetaObject::invokeMethod(m_item, "renderReady", Qt::QueuedConnection);
    }

    std::shared_ptr<mpv_handle> m_mpv[2];
    MpvItem *m_item;
    mpv_render_context *m_ctx[2] = {nullptr, nullptr};
    int m_active = 0;
};

/// Named arguments for loadfile: the position of "options" differs between mpv versions.
void loadFile(mpv_handle *mpv, const QString &path, const QVariantMap &options)
{
    QList<QByteArray> keys, values;
    for (auto it = options.begin(); it != options.end(); ++it) {
        keys.append(it.key().toUtf8());
        values.append(it.value().toString().toUtf8());
    }
    const auto str = [](QByteArray &v) {
        mpv_node n{};
        n.format = MPV_FORMAT_STRING;
        n.u.string = v.data();
        return n;
    };
    QList<mpv_node> optValues;
    QList<char *> optKeys;
    for (qsizetype i = 0; i < keys.size(); ++i) {
        optValues.append(str(values[i]));
        optKeys.append(keys[i].data());
    }
    mpv_node_list opts{int(keys.size()), optValues.data(), optKeys.data()};
    mpv_node optsNode{};
    optsNode.format = MPV_FORMAT_NODE_MAP;
    optsNode.u.list = &opts;

    QByteArray name = "loadfile", url = path.toUtf8(), flags = "replace";
    char argKeys[][8] = {"name", "url", "flags", "options"};
    mpv_node argValues[] = {str(name), str(url), str(flags), optsNode};
    char *argKeyPtrs[] = {argKeys[0], argKeys[1], argKeys[2], argKeys[3]};
    mpv_node_list args{4, argValues, argKeyPtrs};
    mpv_node cmd{};
    cmd.format = MPV_FORMAT_NODE_MAP;
    cmd.u.list = &args;
    mpv_command_node_async(mpv, 0, &cmd);
}

} // namespace

MpvItem::MpvItem(QQuickItem *parent) : QQuickFramebufferObject(parent)
{
    for (int p = 0; p < 2; ++p) {
        m_mpv[p] = std::shared_ptr<mpv_handle>(mpv_create(), mpv_terminate_destroy);
        if (!m_mpv[p])
            qFatal("mpv konnte nicht gestartet werden");
        mpv_handle *mpv = handle(p);
        for (const auto &[key, value] : std::initializer_list<std::pair<const char *, const char *>>{
                 {"vo", "libmpv"},
                 {"hwdec", "auto-safe"},
                 // Stay on the last frame at the end instead of closing the file.
                 {"keep-open", "yes"},
                 {"idle", "yes"},
                 {"hr-seek", "yes"},
                 {"input-default-bindings", "no"},
                 {"input-vo-keyboard", "no"},
                 {"osc", "no"},
                 {"osd-level", "0"},
                 // Music shows the visualizer, never its cover.
                 {"audio-display", "no"},
                 {"load-scripts", "no"},
                 {"ytdl", "no"},
             })
            mpv_set_option_string(mpv, key, value);
        if (mpv_initialize(mpv) < 0)
            qFatal("mpv konnte nicht initialisiert werden");

        mpv_request_log_messages(mpv, "error");
        mpv_observe_property(mpv, TimePos, "time-pos", MPV_FORMAT_DOUBLE);
        mpv_observe_property(mpv, Pause, "pause", MPV_FORMAT_FLAG);
        mpv_observe_property(mpv, EofReached, "eof-reached", MPV_FORMAT_FLAG);
        mpv_set_wakeup_callback(
            mpv,
            [](void *data) {
                const auto *w = static_cast<Wakeup *>(data);
                MpvItem *item = w->item;
                const int player = w->player;
                QMetaObject::invokeMethod(item, [item, player] { item->processEvents(player); }, Qt::QueuedConnection);
            },
            &m_wakeup[p]);
    }
}

MpvItem::~MpvItem()
{
    for (int p = 0; p < 2; ++p)
        mpv_set_wakeup_callback(handle(p), nullptr, nullptr);
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const
{
    return new MpvRenderer(m_mpv[0], m_mpv[1], const_cast<MpvItem *>(this));
}

void MpvItem::setPaused(bool paused)
{
    // The waiting player always stays paused.
    int flag = paused;
    mpv_set_property_async(handle(m_active), 0, "pause", MPV_FORMAT_FLAG, &flag);
    // Callers read the state right after setting it; mpv confirms asynchronously.
    if (m_paused != paused) {
        m_paused = paused;
        emit pausedChanged();
    }
}

void MpvItem::setVolume(double volume)
{
    double percent = volume * 100;
    for (int p = 0; p < 2; ++p)
        mpv_set_property_async(handle(p), 0, "volume", MPV_FORMAT_DOUBLE, &percent);
    if (m_volume != volume) {
        m_volume = volume;
        emit volumeChanged();
    }
}

void MpvItem::setMuted(bool muted)
{
    int flag = muted;
    for (int p = 0; p < 2; ++p)
        mpv_set_property_async(handle(p), 0, "mute", MPV_FORMAT_FLAG, &flag);
    if (m_muted != muted) {
        m_muted = muted;
        emit mutedChanged();
    }
}

void MpvItem::setBackground(const QColor &color)
{
    for (int p = 0; p < 2; ++p)
        mpv_set_property_string(handle(p), "background-color", color.name().toUtf8().constData());
    if (m_background != color) {
        m_background = color;
        emit backgroundChanged();
        update();
    }
}

void MpvItem::renderReady()
{
    m_renderReady = true;
    if (!m_path.isEmpty())
        load(m_path);
}

void MpvItem::load(const QString &path, double start)
{
    m_path = path;
    // Video initialization fails without a render context; renderReady() catches up.
    if (!m_renderReady)
        return;
    m_sequence = false;
    m_switchTarget = -1;
    prepare(1 - m_active, -1);
    mpv_handle *mpv = handle(m_active);
    m_checkAudio = true;
    m_loadTimer.start();
    setLoop(-1, -1);
    // Opening right at `start` saves a second seek and decoding up to it.
    mpv_set_property_string(mpv, "start", start > 0 ? QByteArray::number(start, 'f', 6).constData() : "none");
    setPaused(false);
    if (m_playlistPos != 0) {
        m_playlistPos = 0;
        emit playlistPosChanged();
    }
    const QByteArray file = path.toUtf8();
    const char *cmd[] = {"loadfile", file.constData(), nullptr};
    mpv_command_async(mpv, 0, cmd);
}

void MpvItem::loadSequence(const QVariantList &entries)
{
    if (entries.isEmpty() || !m_renderReady)
        return;
    m_sequence = true;
    m_entries = entries;
    m_switchTarget = -1;
    m_entry[0] = m_entry[1] = -1;
    m_path = entries.first().toMap()["path"].toString();
    m_checkAudio = true;
    m_loadTimer.start();
    setLoop(-1, -1);
    if (m_eof) {
        m_eof = false;
        emit eofChanged();
    }
    loadEntry(m_active, 0, m_paused);
    prepare(1 - m_active, 1);
}

void MpvItem::loadEntry(int player, int entry, bool paused)
{
    const QVariantMap e = m_entries[entry].toMap();
    mpv_handle *mpv = handle(player);
    int flag = paused;
    mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag);
    // keep-open would pause at the end of each clip, and that pause could reach us before
    // the end itself and be taken for the user's: the next clip would start paused.
    loadFile(mpv, e["path"].toString(),
             {{"start", QString::number(e["start"].toDouble(), 'f', 6)},
              {"end", QString::number(e["end"].toDouble(), 'f', 6)},
              {"aid", e["muted"].toBool() ? "no" : "auto"},
              {"keep-open-pause", "no"}});
    m_entry[player] = entry;
    m_fileLoaded[player] = false;
    m_ready[player] = false;
}

void MpvItem::prepare(int player, int entry)
{
    if (entry < 0 || entry >= m_entries.size() || !m_sequence) {
        const char *cmd[] = {"stop", nullptr};
        mpv_command_async(handle(player), 0, cmd);
        m_entry[player] = -1;
        m_ready[player] = false;
        return;
    }
    loadEntry(player, entry, true);
}

void MpvItem::switchTo(int player)
{
    const int other = 1 - player;
    m_active = player;
    m_switchTarget = -1;
    int flag = 1;
    mpv_set_property_async(handle(other), 0, "pause", MPV_FORMAT_FLAG, &flag);
    flag = m_paused;
    mpv_set_property_async(handle(player), 0, "pause", MPV_FORMAT_FLAG, &flag);
    update();

    const QVariantMap e = m_entries[m_entry[player]].toMap();
    m_path = e["path"].toString();
    readInfo(player);
    m_playlistPos = m_entry[player];
    emit playlistPosChanged();
    m_position = e["start"].toDouble();
    emit positionChanged();
    if (!m_loaded) {
        m_loaded = true;
        emit loadedChanged();
    }
    if (m_eof) {
        m_eof = false;
        emit eofChanged();
    }
    emit fileLoaded();
    prepare(other, m_entry[player] + 1);
}

void MpvItem::setAudioOff(bool off)
{
    mpv_set_property_string(handle(m_active), "aid", off ? "no" : "auto");
}

void MpvItem::playIndex(int index)
{
    if (!m_sequence || index < 0 || index >= m_entries.size())
        return;
    const int other = 1 - m_active;
    if (m_entry[m_active] == index) {
        // Already there; a loaded entry announces itself again for the caller's seek.
        if (m_fileLoaded[m_active])
            emit fileLoaded();
        return;
    }
    if (m_entry[other] == index) {
        if (m_ready[other])
            switchTo(other);
        else
            m_switchTarget = index;
        return;
    }
    m_switchTarget = -1;
    loadEntry(m_active, index, m_paused);
    prepare(other, index + 1);
}

void MpvItem::unload()
{
    m_sequence = false;
    const char *cmd[] = {"stop", nullptr};
    mpv_command_async(handle(1 - m_active), 0, cmd);
    mpv_command_async(handle(m_active), 0, cmd);
}

void MpvItem::seek(double sec)
{
    const QByteArray target = QByteArray::number(sec, 'f', 6);
    const char *cmd[] = {"seek", target.constData(), "absolute+exact", nullptr};
    mpv_command_async(handle(m_active), 0, cmd);
}

void MpvItem::setLoop(double a, double b)
{
    const bool on = a >= 0 && b > a;
    mpv_handle *mpv = handle(m_active);
    mpv_set_property_string(mpv, "ab-loop-a", on ? QByteArray::number(a, 'f', 6).constData() : "no");
    mpv_set_property_string(mpv, "ab-loop-b", on ? QByteArray::number(b, 'f', 6).constData() : "no");
}

bool MpvItem::readInfo(int player)
{
    mpv_handle *mpv = handle(player);
    const auto num = [mpv](const char *name, double fallback) {
        double v;
        return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &v) >= 0 ? v : fallback;
    };
    const auto str = [mpv](const char *name) {
        char *v = mpv_get_property_string(mpv, name);
        const QString s = QString::fromUtf8(v);
        mpv_free(v);
        return s;
    };
    m_duration = num("duration", 0);
    m_width = int(num("current-tracks/video/demux-w", 0));
    m_height = int(num("current-tracks/video/demux-h", 0));
    m_fps = num("current-tracks/video/demux-fps", num("container-fps", 0));
    m_hasAudio = num("current-tracks/audio/id", -1) >= 0;
    m_hasVideo = num("current-tracks/video/id", -1) >= 0;
    m_codec = str(m_hasVideo ? "current-tracks/video/codec" : "current-tracks/audio/codec");
    m_title = str("media-title");
    m_artist = str("metadata/by-key/artist");
    emit infoChanged();
    return m_hasVideo || m_hasAudio;
}

void MpvItem::processEvents(int player)
{
    mpv_handle *mpv = handle(player);
    while (true) {
        mpv_event *ev = mpv_wait_event(mpv, 0);
        if (ev->event_id == MPV_EVENT_NONE)
            return;
        if (ev->event_id == MPV_EVENT_LOG_MESSAGE) {
            const auto *msg = static_cast<mpv_event_log_message *>(ev->data);
            qWarning("mpv/%s: %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
            continue;
        }
        // The waiting player only reports when the next clip is ready.
        if (player != m_active) {
            if (ev->event_id == MPV_EVENT_FILE_LOADED) {
                m_fileLoaded[player] = true;
            } else if (ev->event_id == MPV_EVENT_PLAYBACK_RESTART && m_entry[player] >= 0) {
                m_ready[player] = true;
                if (m_switchTarget == m_entry[player])
                    switchTo(player);
            }
            continue;
        }
        switch (ev->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE: {
            const auto *p = static_cast<mpv_event_property *>(ev->data);
            if (ev->reply_userdata == TimePos && p->format == MPV_FORMAT_DOUBLE) {
                m_position = *static_cast<double *>(p->data);
                emit positionChanged();
            } else if (ev->reply_userdata == Pause && p->format == MPV_FORMAT_FLAG) {
                const bool paused = *static_cast<int *>(p->data);
                if (paused != m_paused) {
                    m_paused = paused;
                    emit pausedChanged();
                }
            } else if (ev->reply_userdata == EofReached) {
                const bool eof = p->format == MPV_FORMAT_FLAG && *static_cast<int *>(p->data);
                const int next = m_entry[player] + 1;
                if (eof && m_sequence && next < m_entries.size()) {
                    // A clip of the sequence is over: the next one waits on the other player.
                    const int other = 1 - player;
                    if (m_entry[other] == next && m_ready[other])
                        switchTo(other);
                    else if (m_entry[other] == next)
                        m_switchTarget = next;
                    else
                        playIndex(next);
                } else if (eof != m_eof) {
                    m_eof = eof;
                    emit eofChanged();
                }
            }
            break;
        }
        case MPV_EVENT_FILE_LOADED:
            m_fileLoaded[player] = true;
            if (!readInfo(player)) {
                emit loadFailed(QStringLiteral("Weder Bild noch Ton gefunden"));
                unload();
                break;
            }
            if (m_sequence && m_entry[player] != m_playlistPos) {
                m_playlistPos = m_entry[player];
                emit playlistPosChanged();
            }
            m_loaded = true;
            emit loadedChanged();
            emit fileLoaded();
            break;
        case MPV_EVENT_VIDEO_RECONFIG:
            // Some containers carry no dimensions; the decoder knows them.
            if (m_loaded && m_width <= 0) {
                int64_t w = 0, h = 0;
                mpv_get_property(mpv, "width", MPV_FORMAT_INT64, &w);
                mpv_get_property(mpv, "height", MPV_FORMAT_INT64, &h);
                m_width = int(w);
                m_height = int(h);
                emit infoChanged();
            }
            break;
        case MPV_EVENT_PLAYBACK_RESTART:
            m_ready[player] = true;
            if (m_checkAudio && m_loaded) {
                m_checkAudio = false;
                char *hwdec = mpv_get_property_string(mpv, "hwdec-current");
                qInfo("mpv: %s %dx%d, Hardware-Dekodierung: %s, geladen in %lld ms", qPrintable(m_codec),
                      m_width, m_height, hwdec ? hwdec : "keine", m_loadTimer.elapsed());
                mpv_free(hwdec);
                char *ao = mpv_get_property_string(mpv, "current-ao");
                if (m_hasAudio && !ao)
                    emit noAudioOutput();
                mpv_free(ao);
            }
            break;
        case MPV_EVENT_END_FILE: {
            const auto *end = static_cast<mpv_event_end_file *>(ev->data);
            if (end->reason == MPV_END_FILE_REASON_ERROR) {
                qWarning("mpv: %s nicht abspielbar: %s", qPrintable(m_path), mpv_error_string(end->error));
                emit loadFailed(QStringLiteral("Wiedergabe nicht möglich: %1").arg(mpv_error_string(end->error)));
            }
            if (m_loaded) {
                m_loaded = false;
                emit loadedChanged();
            }
            emit closed();
            break;
        }
        default:
            break;
        }
    }
}
