#include "thumbnailer.h"

#include "exportjob.h"
#include "files.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QUrl>

void Thumbnailer::start(const QString &path, double duration, int count)
{
    cancel();
    m_thumbs.clear();
    emit thumbnailsChanged();
    const qint64 mtime = QFileInfo(path).lastModified().toSecsSinceEpoch();
    m_dir = tempSubdir("thumbs-" + shortHash(QStringLiteral("%1|%2").arg(path).arg(mtime)));
    m_path = path;
    m_duration = duration;
    m_count = count;
    m_index = 0;
    next();
}

void Thumbnailer::cancel()
{
    m_index = m_count;
    if (m_proc) {
        m_proc->disconnect(this);
        connect(m_proc, &QProcess::finished, m_proc, &QObject::deleteLater);
        m_proc->kill();
        m_proc = nullptr;
    }
}

void Thumbnailer::next()
{
    for (; m_index < m_count; ++m_index) {
        const QString target = QDir(m_dir).filePath(QString::asprintf("thumb_%03d.jpg", m_index + 1));
        if (!QFileInfo::exists(target)) {
            extract(target, m_duration * (m_index + 0.5) / m_count, true);
            return;
        }
        m_thumbs.append(QUrl::fromLocalFile(target).toString());
        emit thumbnailsChanged();
    }
}

void Thumbnailer::extract(const QString &target, double ts, bool fast)
{
    auto *proc = new QProcess(this);
    prepareTool(*proc);
    m_proc = proc;
    const auto done = [=, this] {
        proc->deleteLater();
        m_proc = nullptr;
        // Without a keyframe before `ts` (short clips, long GOP) the fast path
        // yields nothing; decode up to `ts` then.
        if (!QFileInfo::exists(target) && fast) {
            extract(target, ts, false);
            return;
        }
        // A seek past the last decodable frame yields nothing; skip that slot.
        if (QFileInfo::exists(target)) {
            m_thumbs.append(QUrl::fromLocalFile(target).toString());
            emit thumbnailsChanged();
        }
        ++m_index;
        next();
    };
    connect(proc, &QProcess::finished, this, done);
    connect(proc, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            proc->deleteLater();
            m_proc = nullptr;
            m_index = m_count;
        }
    });
    proc->start(toolPath("ffmpeg"), thumbnailArgs(m_path, ts, target, fast));
}
