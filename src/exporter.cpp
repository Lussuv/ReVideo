#include "exporter.h"

#include "exportjob.h"
#include "files.h"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <algorithm>

void Exporter::start(const QString &input, const QString &output, double start, double end,
                     int preset, bool hasAudio)
{
    if (m_proc)
        return;
    if (end <= start) {
        emit finished(QStringLiteral("Ende muss nach dem Start liegen"));
        return;
    }
    const double duration = end - start;
    resetProgress(duration);

    if (Preset(preset) == Preset::Original) {
        run(originalArgs(input, output, start, duration), 0, 100, [this] { finish({}); });
        return;
    }
    const QString passlog = QDir(tempSubdir("2pass")).filePath("p-" + shortHash(input));
    const auto pass = [=](int n) { return discordArgs(input, output, start, duration, hasAudio, n, passlog); };
    run(pass(1), 0, 50, [=, this] {
        run(pass(2), 50, 50, [=, this] {
            // x264 writes <passlogfile>-0.log and -0.log.mbtree.
            QFile::remove(passlog + "-0.log");
            QFile::remove(passlog + "-0.log.mbtree");
            finish({});
        });
    });
}

void Exporter::startSequence(const QVariantList &clips, const QString &output, int preset,
                             const QVariantList &music)
{
    if (m_proc || clips.isEmpty())
        return;
    QList<Clip> list;
    QList<Span> mutes;
    double duration = 0;
    bool same = true;
    const QVariantMap first = clips.first().toMap();
    for (const QVariant &v : clips) {
        const QVariantMap m = v.toMap();
        // A muted clip counts as one without audio: re-encoded it gets silence.
        const bool muted = m["muted"].toBool();
        list.append({m["path"].toString(), m["start"].toDouble(), m["end"].toDouble(),
                     m["hasAudio"].toBool() && !muted});
        const double length = list.last().end - list.last().start;
        if (muted)
            mutes.append({duration, duration + length});
        duration += length;
        same = same && m["signature"] == first["signature"];
    }
    resetProgress(duration);
    const int width = first["width"].toInt(), height = first["height"].toInt();
    QList<Music> songs;
    for (const QVariant &v : music) {
        const QVariantMap m = v.toMap();
        songs.append({m["path"].toString(), m["offset"].toDouble(), m["volume"].toDouble(),
                      m["start"].toDouble(), m["length"].toDouble()});
    }

    if (Preset(preset) == Preset::Original && same) {
        const QString listFile = QDir(tempSubdir("concat")).filePath("list-" + shortHash(output) + ".txt");
        QFile file(listFile);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            finish(QStringLiteral("Clip-Liste konnte nicht geschrieben werden: %1").arg(file.errorString()));
            return;
        }
        file.write(concatList(list).toUtf8());
        file.close();
        run(concatCopyArgs(listFile, output, songs, first["hasAudio"].toBool(), duration, mutes), 0, 100,
            [=, this] {
                QFile::remove(listFile);
                finish({});
            });
    } else if (Preset(preset) == Preset::Original) {
        const double fps = first["fps"].toDouble();
        run(concatOriginalArgs(list, width, height, fps > 0 ? fps : 30, output, songs), 0, 100,
            [this] { finish({}); });
    } else {
        const QString passlog = QDir(tempSubdir("2pass")).filePath("p-" + shortHash(output));
        const auto pass = [=](int n) { return concatDiscordArgs(list, width, height, n, passlog, output, songs); };
        run(pass(1), 0, 50, [=, this] {
            run(pass(2), 50, 50, [=, this] {
                QFile::remove(passlog + "-0.log");
                QFile::remove(passlog + "-0.log.mbtree");
                finish({});
            });
        });
    }
}

void Exporter::resetProgress(double duration)
{
    m_durationUs = qint64(duration * 1e6);
    m_percent = 0;
    m_speed.clear();
    m_eta = 0;
    emit progressChanged();
}

void Exporter::run(const QStringList &args, double offset, double scale, std::function<void()> next)
{
    auto *proc = new QProcess(this);
    prepareTool(*proc);
    const bool wasRunning = m_proc != nullptr;
    m_proc = proc;
    if (!wasRunning)
        emit runningChanged();

    auto outUs = std::make_shared<qint64>(0);
    auto speed = std::make_shared<QString>();
    connect(proc, &QProcess::readyReadStandardOutput, this, [=, this] {
        while (proc->canReadLine()) {
            const QString line = QString::fromUtf8(proc->readLine()).trimmed();
            const auto eq = line.indexOf('=');
            const QString key = line.left(eq), value = line.mid(eq + 1).trimmed();
            // Older builds wrote microseconds under out_time_ms too; accept both.
            if (key == "out_time_us" || key == "out_time_ms") {
                bool ok = false;
                const qint64 v = value.toLongLong(&ok);
                if (ok)
                    *outUs = v;
            } else if (key == "speed") {
                *speed = value;
            } else if (key == "progress") {
                const Progress p = progressFor(*outUs, *speed, m_durationUs, offset, scale);
                m_percent = p.percent;
                m_speed = p.speed;
                m_eta = p.etaSec;
                emit progressChanged();
            }
        }
    });
    connect(proc, &QProcess::finished, this, [=, this](int code, QProcess::ExitStatus status) {
        proc->deleteLater();
        if (status != QProcess::NormalExit || code != 0) {
            const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            finish(QStringLiteral("ffmpeg beendet mit %1: %2").arg(code).arg(err));
            return;
        }
        next();
    });
    connect(proc, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        proc->deleteLater();
        finish(QStringLiteral("ffmpeg konnte nicht gestartet werden: %1").arg(proc->errorString()));
    });
    proc->start(toolPath("ffmpeg"), QStringList{"-progress", "pipe:1", "-nostats", "-v", "error"} + args);
}

void Exporter::saveFrame(const QString &input, double frameStart, double frameDuration,
                         const QString &output)
{
    // ffmpeg outputs the first frame at or after the target; aiming half a frame
    // early keeps rounding from landing on the next one.
    const double ts = std::max(frameStart - frameDuration / 2, 0.0);
    auto *proc = new QProcess(this);
    prepareTool(*proc);
    connect(proc, &QProcess::finished, this, [=, this](int code, QProcess::ExitStatus status) {
        proc->deleteLater();
        emit frameSaved(status == QProcess::NormalExit && code == 0
                            ? QString()
                            : QStringLiteral("Frame konnte nicht gespeichert werden: %1")
                                  .arg(QString::fromUtf8(proc->readAllStandardError()).trimmed()));
    });
    connect(proc, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        proc->deleteLater();
        emit frameSaved(QStringLiteral("ffmpeg konnte nicht gestartet werden: %1").arg(proc->errorString()));
    });
    proc->start(toolPath("ffmpeg"), frameArgs(input, ts, output));
}

void Exporter::finish(const QString &error)
{
    m_proc = nullptr;
    if (error.isEmpty()) {
        m_percent = 100;
        emit progressChanged();
    }
    emit runningChanged();
    emit finished(error);
}
