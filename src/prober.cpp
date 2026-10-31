#include "prober.h"

#include "exportjob.h"
#include "files.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QUrl>

/// Runs ffmpeg and hands its stderr and stdout to `done`; both empty if it could not start.
static void runTool(QObject *owner, const QStringList &args,
                    std::function<void(const QString &, const QByteArray &)> done)
{
    auto *proc = new QProcess(owner);
    prepareTool(*proc);
    QObject::connect(proc, &QProcess::finished, owner, [=] {
        proc->deleteLater();
        done(QString::fromUtf8(proc->readAllStandardError()), proc->readAllStandardOutput());
    });
    QObject::connect(proc, &QProcess::errorOccurred, owner, [=](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        proc->deleteLater();
        done({}, {});
    });
    proc->start(toolPath("ffmpeg"), args);
}

void Prober::probe(const QString &path)
{
    // ffmpeg exits with an error without an output file; only its stream listing counts.
    runTool(this, probeArgs(path), [=, this](const QString &log, const QByteArray &) {
        const auto info = parseMediaInfo(log);
        if (!info) {
            emit probed(path, {});
            return;
        }
        QVariantMap map = {{"duration", info->duration}, {"hasVideo", info->hasVideo}, {"width", info->width},
                           {"height", info->height},     {"fps", info->fps},
                           {"hasAudio", info->hasAudio}, {"signature", info->signature}};
        const qint64 mtime = QFileInfo(path).lastModified().toSecsSinceEpoch();
        const QString target = QDir(tempSubdir("thumbs-" + shortHash(QStringLiteral("%1|%2").arg(path).arg(mtime))))
                                   .filePath("clip.jpg");
        const auto finish = [=, this] {
            QVariantMap result = map;
            result["thumb"] = QFileInfo::exists(target) ? QUrl::fromLocalFile(target).toString() : QString();
            emit probed(path, result);
        };
        if (!info->hasVideo) {
            // Music: its waveform instead of a thumbnail.
            runTool(this, waveformArgs(path), [=, this](const QString &, const QByteArray &pcm) {
                QVariantList peaks;
                for (float p : waveformPeaks(pcm, WAVEFORM_RATE, 20))
                    peaks.append(p);
                QVariantMap result = map;
                result["peaks"] = peaks;
                emit probed(path, result);
            });
        } else if (QFileInfo::exists(target)) {
            finish();
        } else {
            runTool(this, thumbnailArgs(path, {{info->duration * 0.1, target}}, false),
                    [=](const QString &, const QByteArray &) { finish(); });
        }
    });
}
