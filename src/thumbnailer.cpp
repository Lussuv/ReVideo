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
    const qint64 mtime = QFileInfo(path).lastModified().toSecsSinceEpoch();
    m_dir = tempSubdir("thumbs-" + shortHash(QStringLiteral("%1|%2").arg(path).arg(mtime)));
    m_path = path;
    m_duration = duration;
    m_count = count;
    publish();
    run(true);
}

void Thumbnailer::cancel()
{
    if (m_proc) {
        m_proc->disconnect(this);
        connect(m_proc, &QProcess::finished, m_proc, &QObject::deleteLater);
        m_proc->kill();
        m_proc = nullptr;
    }
}

QString Thumbnailer::target(int slot) const
{
    return QDir(m_dir).filePath(QString::asprintf("thumb_%03d.jpg", slot + 1));
}

void Thumbnailer::run(bool fast)
{
    QList<Thumb> missing;
    for (int i = 0; i < m_count; ++i)
        if (!QFileInfo::exists(target(i)))
            missing.append({m_duration * (i + 0.5) / m_count, target(i)});
    if (missing.isEmpty())
        return;

    auto *proc = new QProcess(this);
    prepareTool(*proc);
    m_proc = proc;
    // A failed slot (no keyframe after it, seek past the last frame) only means a
    // missing file; ffmpeg's exit code says nothing about the others.
    const auto done = [=, this] {
        proc->deleteLater();
        m_proc = nullptr;
        publish();
        if (fast)
            run(false);
    };
    connect(proc, &QProcess::finished, this, done);
    connect(proc, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            proc->deleteLater();
            m_proc = nullptr;
        }
    });
    proc->start(toolPath("ffmpeg"), thumbnailArgs(m_path, missing, fast));
}

void Thumbnailer::publish()
{
    QStringList thumbs;
    for (int i = 0; i < m_count; ++i)
        thumbs.append(QFileInfo::exists(target(i)) ? QUrl::fromLocalFile(target(i)).toString() : QString());
    if (thumbs != m_thumbs) {
        m_thumbs = thumbs;
        emit thumbnailsChanged();
    }
}
