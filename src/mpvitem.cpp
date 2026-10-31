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
    MpvRenderer(std::shared_ptr<mpv_handle> mpv, MpvItem *item) : m_mpv(std::move(mpv)), m_item(item) {}

    // Runs on the render thread; must happen before the mpv handle goes away,
    // which the shared handle guarantees.
    ~MpvRenderer() override
    {
        if (m_ctx)
            mpv_render_context_free(m_ctx);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_ctx)
            init();
        return new QOpenGLFramebufferObject(size);
    }

    void render() override
    {
        if (!m_ctx)
            return;
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo target{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flip = 0;
        mpv_render_param params[] = {{MPV_RENDER_PARAM_OPENGL_FBO, &target},
                                     {MPV_RENDER_PARAM_FLIP_Y, &flip},
                                     {MPV_RENDER_PARAM_INVALID, nullptr}};
        mpv_render_context_render(m_ctx, params);
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
        if (mpv_render_context_create(&m_ctx, m_mpv.get(), params.data()) < 0) {
            qWarning("mpv: Render-Kontext konnte nicht erstellt werden");
            m_ctx = nullptr;
            return;
        }
        mpv_render_context_set_update_callback(
            m_ctx,
            [](void *item) {
                QMetaObject::invokeMethod(static_cast<MpvItem *>(item), "update", Qt::QueuedConnection);
            },
            m_item);
        QMetaObject::invokeMethod(m_item, "renderReady", Qt::QueuedConnection);
    }

    std::shared_ptr<mpv_handle> m_mpv;
    MpvItem *m_item;
    mpv_render_context *m_ctx = nullptr;
};

} // namespace

MpvItem::MpvItem(QQuickItem *parent)
    : QQuickFramebufferObject(parent), m_mpv(mpv_create(), mpv_terminate_destroy)
{
    if (!m_mpv)
        qFatal("mpv konnte nicht gestartet werden");
    mpv_handle *mpv = m_mpv.get();
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
        [](void *self) {
            auto *item = static_cast<MpvItem *>(self);
            QMetaObject::invokeMethod(item, [item] { item->processEvents(); }, Qt::QueuedConnection);
        },
        this);
}

MpvItem::~MpvItem()
{
    mpv_set_wakeup_callback(m_mpv.get(), nullptr, nullptr);
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const
{
    return new MpvRenderer(m_mpv, const_cast<MpvItem *>(this));
}

void MpvItem::setPaused(bool paused)
{
    int flag = paused;
    mpv_set_property_async(m_mpv.get(), 0, "pause", MPV_FORMAT_FLAG, &flag);
    // Callers read the state right after setting it; mpv confirms asynchronously.
    if (m_paused != paused) {
        m_paused = paused;
        emit pausedChanged();
    }
}

void MpvItem::setVolume(double volume)
{
    double percent = volume * 100;
    mpv_set_property_async(m_mpv.get(), 0, "volume", MPV_FORMAT_DOUBLE, &percent);
    if (m_volume != volume) {
        m_volume = volume;
        emit volumeChanged();
    }
}

void MpvItem::setMuted(bool muted)
{
    int flag = muted;
    mpv_set_property_async(m_mpv.get(), 0, "mute", MPV_FORMAT_FLAG, &flag);
    if (m_muted != muted) {
        m_muted = muted;
        emit mutedChanged();
    }
}

void MpvItem::setBackground(const QColor &color)
{
    mpv_set_property_string(m_mpv.get(), "background-color", color.name().toUtf8().constData());
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

void MpvItem::load(const QString &path)
{
    mpv_handle *mpv = m_mpv.get();
    m_path = path;
    // Video initialization fails without a render context; renderReady() catches up.
    if (!m_renderReady)
        return;
    m_checkAudio = true;
    setLoop(-1, -1);
    setPaused(false);
    const QByteArray file = path.toUtf8();
    const char *cmd[] = {"loadfile", file.constData(), nullptr};
    mpv_command_async(mpv, 0, cmd);
}

void MpvItem::unload()
{
    const char *cmd[] = {"stop", nullptr};
    mpv_command_async(m_mpv.get(), 0, cmd);
}

void MpvItem::seek(double sec)
{
    const QByteArray target = QByteArray::number(sec, 'f', 6);
    const char *cmd[] = {"seek", target.constData(), "absolute+exact", nullptr};
    mpv_command_async(m_mpv.get(), 0, cmd);
}

void MpvItem::setLoop(double a, double b)
{
    const bool on = a >= 0 && b > a;
    mpv_set_property_string(m_mpv.get(), "ab-loop-a", on ? QByteArray::number(a, 'f', 6).constData() : "no");
    mpv_set_property_string(m_mpv.get(), "ab-loop-b", on ? QByteArray::number(b, 'f', 6).constData() : "no");
}

bool MpvItem::readInfo()
{
    mpv_handle *mpv = m_mpv.get();
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
    m_codec = str("current-tracks/video/codec");
    m_hasAudio = num("current-tracks/audio/id", -1) >= 0;
    emit infoChanged();
    return num("current-tracks/video/id", -1) >= 0;
}

void MpvItem::processEvents()
{
    mpv_handle *mpv = m_mpv.get();
    while (true) {
        mpv_event *ev = mpv_wait_event(mpv, 0);
        switch (ev->event_id) {
        case MPV_EVENT_NONE:
            return;
        case MPV_EVENT_LOG_MESSAGE: {
            const auto *msg = static_cast<mpv_event_log_message *>(ev->data);
            qWarning("mpv/%s: %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
            break;
        }
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
                if (eof != m_eof) {
                    m_eof = eof;
                    emit eofChanged();
                }
            }
            break;
        }
        case MPV_EVENT_FILE_LOADED:
            if (!readInfo()) {
                emit loadFailed(QStringLiteral("Keine Videospur gefunden"));
                unload();
                break;
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
            if (m_checkAudio && m_loaded) {
                m_checkAudio = false;
                char *hwdec = mpv_get_property_string(mpv, "hwdec-current");
                qInfo("mpv: %s %dx%d, Hardware-Dekodierung: %s", qPrintable(m_codec), m_width,
                      m_height, hwdec ? hwdec : "keine");
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
