#include "exportjob.h"

#include <algorithm>
#include <cmath>

static QString secs(double v)
{
    return QString::number(v, 'f', 3);
}

static const int AUDIO_KBPS = 96;

Progress progressFor(qint64 outUs, const QString &speed, qint64 durationUs, double offset, double scale)
{
    const double raw =
        durationUs == 0 ? 0 : std::clamp(double(outUs) / double(durationUs) * 100.0, 0.0, 100.0);
    QString factorText = speed.trimmed();
    if (factorText.endsWith('x'))
        factorText.chop(1);
    bool ok = false;
    double factor = factorText.trimmed().toDouble(&ok);
    factor = std::max(ok ? factor : 1.0, 0.05);
    return {std::clamp(offset + raw * scale / 100.0, 0.0, 99.5), speed,
            double(std::max<qint64>(durationUs - outUs, 0)) / 1e6 / factor};
}

QStringList originalArgs(const QString &input, const QString &output, double start, double duration)
{
    return {"-y", "-ss", secs(start), "-i", input, "-t", secs(duration), "-c", "copy",
            "-avoid_negative_ts", "make_zero", output};
}

qint64 discordVideoKbps(double duration, bool hasAudio)
{
    // Target 9.3 MB so AAC headers / MP4 moov atom never push us over 10.
    const double targetBits = 9'300'000.0 * 8;
    const double audioKbps = hasAudio ? AUDIO_KBPS : 0;
    const double videoBits = std::max(targetBits - audioKbps * 1000 * duration, 50'000.0);
    return qint64(std::floor(std::max(videoBits / duration / 1000, 50.0)));
}

QStringList discordArgs(const QString &input, const QString &output, double start, double duration,
                        bool hasAudio, int pass, const QString &passlog)
{
    QStringList args = {
        "-y", "-ss", secs(start), "-i", input, "-t", secs(duration),
        "-c:v", "libx264", "-b:v", QString::number(discordVideoKbps(duration, hasAudio)) + "k",
        "-vf", "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,fps=30",
        "-passlogfile", passlog, "-pass", QString::number(pass),
        // In both passes: x264 refuses a second pass with another bit depth (10-bit sources).
        "-pix_fmt", "yuv420p",
    };
    if (pass == 1) {
#ifdef Q_OS_WIN
        args << "-an" << "-f" << "mp4" << "NUL";
#else
        args << "-an" << "-f" << "mp4" << "/dev/null";
#endif
        return args;
    }
    if (hasAudio)
        args << "-c:a" << "aac" << "-b:a" << QString::number(AUDIO_KBPS) + "k";
    else
        args << "-an";
    args << "-movflags" << "+faststart" << output;
    return args;
}

QStringList frameArgs(const QString &input, double ts, const QString &output)
{
    return {"-y", "-v", "error", "-ss", QString::number(ts, 'f', 6), "-i", input,
            "-frames:v", "1", "-update", "1", output};
}

QStringList thumbnailArgs(const QString &input, const QList<Thumb> &thumbs, bool fast)
{
    QStringList args = {"-y", "-v", "error"};
    for (const Thumb &t : thumbs) {
        // Single-threaded on purpose: frame threading makes the decoder fill a frame per
        // core before the first one comes out (~100 ms instead of ~600 ms per 4K thumbnail).
        if (fast)
            args << "-noaccurate_seek" << "-threads" << "1" << "-skip_frame" << "nokey";
        args << "-ss" << secs(t.ts) << "-i" << input;
    }
    for (qsizetype i = 0; i < thumbs.size(); ++i)
        args << "-map" << QStringLiteral("%1:v:0").arg(i) << "-frames:v" << "1" << "-vf"
             << "scale=160:-2" << "-q:v" << "5" << thumbs[i].target;
    return args;
}
