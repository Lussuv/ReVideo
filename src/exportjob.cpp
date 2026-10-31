#include "exportjob.h"

#include <QRegularExpression>
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

QStringList probeArgs(const QString &input)
{
    return {"-hide_banner", "-i", input};
}

/// Splits a stream description at ", " outside of parentheses.
static QStringList streamParts(const QString &desc)
{
    QStringList parts;
    int depth = 0, from = 0;
    for (int i = 0; i < desc.size(); ++i) {
        if (desc[i] == '(')
            ++depth;
        else if (desc[i] == ')')
            --depth;
        else if (depth == 0 && desc.mid(i, 2) == ", ") {
            parts << desc.mid(from, i - from);
            from = i + 2;
        }
    }
    return parts << desc.mid(from);
}

std::optional<MediaInfo> parseMediaInfo(const QString &log)
{
    static const QRegularExpression durationRe(R"(^Duration: (\d+):(\d+):(\d+(?:\.\d+)?))");
    static const QRegularExpression rotationRe(R"(rotation of (-?\d+(?:\.\d+)?) degrees)",
                                               QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression sizeRe(R"(^(\d+)x(\d+))");
    static const QRegularExpression fpsRe(R"(^(\d+(?:\.\d+)?)(k?) (fps|tbr)$)");

    MediaInfo info;
    QStringList video, audio;
    QString rotation = "0";
    bool inVideo = false;
    for (const QString &raw : log.split('\n')) {
        const QString line = raw.trimmed();
        if (const auto m = durationRe.match(line); m.hasMatch()) {
            info.duration = m.captured(1).toDouble() * 3600 + m.captured(2).toDouble() * 60 + m.captured(3).toDouble();
        } else if (line.startsWith("Stream #")) {
            inVideo = false;
            const qsizetype v = line.indexOf(" Video: "), a = line.indexOf(" Audio: ");
            if (v >= 0 && video.isEmpty() && !line.contains("(attached pic)")) {
                video = streamParts(line.mid(v + 8));
                inVideo = true;
            } else if (a >= 0 && audio.isEmpty()) {
                audio = streamParts(line.mid(a + 8));
            }
        } else if (const auto m = rotationRe.match(line); inVideo && m.hasMatch()) {
            rotation = m.captured(1);
        }
    }
    if (video.isEmpty() && audio.isEmpty())
        return std::nullopt;
    info.hasVideo = !video.isEmpty();

    QString size, fps;
    for (const QString &part : video) {
        if (const auto m = sizeRe.match(part); m.hasMatch() && size.isEmpty()) {
            size = m.captured(0);
            info.width = m.captured(1).toInt();
            info.height = m.captured(2).toInt();
        } else if (const auto f = fpsRe.match(part); f.hasMatch() && fps.isEmpty()) {
            // "fps" comes before "tbr"; tbr is only the fallback.
            fps = f.captured(0);
            info.fps = f.captured(1).toDouble() * (f.captured(2) == "k" ? 1000 : 1);
        }
    }
    if (std::lround(std::abs(rotation.toDouble())) % 180 == 90)
        std::swap(info.width, info.height);
    info.hasAudio = !audio.isEmpty();

    const auto first = [](const QStringList &parts, int i) { return parts.value(i).section(' ', 0, 0).section('(', 0, 0); };
    info.signature = QStringList{first(video, 0), first(video, 1), size, fps, rotation,
                                 first(audio, 0), audio.value(1), audio.value(2)}.join('|');
    return info;
}

QStringList waveformArgs(const QString &input)
{
    return {"-v", "error", "-i", input, "-vn", "-ac", "1", "-ar", QString::number(WAVEFORM_RATE),
            "-f", "s16le", "-"};
}

QList<float> waveformPeaks(const QByteArray &pcm, int sampleRate, int perSecond)
{
    const auto *samples = reinterpret_cast<const qint16 *>(pcm.constData());
    const qsizetype count = pcm.size() / 2;
    const qsizetype bucket = std::max(sampleRate / perSecond, 1);
    QList<float> peaks;
    float loudest = 0;
    for (qsizetype from = 0; from < count; from += bucket) {
        int peak = 0;
        for (qsizetype i = from; i < std::min(from + bucket, count); ++i)
            peak = std::max(peak, std::abs(int(samples[i])));
        peaks.append(float(peak));
        loudest = std::max(loudest, float(peak));
    }
    if (loudest > 0)
        for (float &p : peaks)
            p /= loudest;
    return peaks;
}

QString concatList(const QList<Clip> &clips)
{
    QString list = "ffconcat version 1.0\n";
    for (const Clip &c : clips) {
        // Inside single quotes only the quote itself needs escaping.
        QString path = c.path;
        path.replace("'", R"('\'')");
        list += QStringLiteral("file '%1'\ninpoint %2\noutpoint %3\n").arg(path, secs(c.start), secs(c.end));
    }
    return list;
}

static const QString STEREO = "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo";

/// Seconds of `music` that play under clips `duration` long; 0 if none.
static double audibleLength(const Music &music, double duration)
{
    const double cut = std::max(-music.offset, 0.0);
    double length = duration - std::max(music.offset, 0.0);
    if (music.length >= 0)
        length = std::min(length, music.length - cut);
    return std::max(length, 0.0);
}

/// Adds the audible part of `music` as the next input.
static void addMusicInput(QStringList &args, const Music &music, double duration)
{
    args << "-ss" << secs(music.start + std::max(-music.offset, 0.0)) << "-t"
         << secs(audibleLength(music, duration)) << "-i" << music.path;
}

/// Filter from input `index` to `[m<n>]`: moved to its place, at its volume.
static QString musicFilter(qsizetype index, qsizetype n, const Music &music)
{
    return QStringLiteral("[%1:a]%2,volume=%3,adelay=%4:all=1[m%5];")
        .arg(index)
        .arg(STEREO)
        .arg(music.volume)
        .arg(qRound64(std::max(music.offset, 0.0) * 1000))
        .arg(n);
}

/// Mixes `labels` into `[a]`, levels unchanged.
static QString mixFilter(const QStringList &labels)
{
    if (labels.size() == 1)
        return labels.first() + "anull[a]";
    return labels.join("") + QStringLiteral("amix=inputs=%1:duration=longest:normalize=0[a]").arg(labels.size());
}

static QList<Music> audible(const QList<Music> &music, double duration)
{
    QList<Music> result;
    for (const Music &m : music)
        if (audibleLength(m, duration) > 0.01)
            result.append(m);
    return result;
}

QStringList concatCopyArgs(const QString &listFile, const QString &output, const QList<Music> &music,
                           bool clipAudio, double duration, const QList<Span> &mutes)
{
    QStringList args = {"-y", "-f", "concat", "-safe", "0", "-i", listFile};
    const QList<Music> songs = audible(music, duration);
    if (songs.isEmpty() && (mutes.isEmpty() || !clipAudio))
        return args << "-c" << "copy" << "-avoid_negative_ts" << "make_zero" << output;
    QString graph;
    QStringList labels;
    if (clipAudio) {
        graph += "[0:a]" + STEREO;
        // Quoted, so that the commas do not split the filter chain.
        for (const Span &m : mutes)
            graph += QStringLiteral(",volume=0:enable='between(t,%1,%2)'").arg(secs(m.from), secs(m.to));
        graph += "[ca];";
        labels << "[ca]";
    }
    for (qsizetype i = 0; i < songs.size(); ++i) {
        addMusicInput(args, songs[i], duration);
        graph += musicFilter(i + 1, i, songs[i]);
        labels << QStringLiteral("[m%1]").arg(i);
    }
    graph += mixFilter(labels);
    return args << "-filter_complex" << graph << "-map" << "0:v" << "-map" << "[a]" << "-c:v" << "copy"
                << "-c:a" << "aac" << "-b:a" << "192k" << "-avoid_negative_ts" << "make_zero" << output;
}

/// Shared by both concat presets; `audioKbps` 0 leaves the audio out, an empty `output`
/// writes to the null device (pass 1).
static QStringList concatEncodeArgs(const QList<Clip> &clips, int width, int height, double fps,
                                    const QStringList &videoArgs, int audioKbps, const QString &output,
                                    const QList<Music> &music)
{
    // x264 with yuv420p needs even dimensions.
    width = std::max(width & ~1, 2);
    height = std::max(height & ~1, 2);
    const bool audio = audioKbps > 0;
    QStringList args = {"-y"};
    for (const Clip &c : clips)
        args << "-ss" << secs(c.start) << "-t" << secs(c.end - c.start) << "-i" << c.path;

    const QString size = QStringLiteral("%1:%2").arg(width).arg(height);
    QString graph, inputs;
    qsizetype silence = clips.size();
    for (qsizetype i = 0; i < clips.size(); ++i) {
        const Clip &c = clips[i];
        graph += QStringLiteral("[%1:v:0]scale=%2:force_original_aspect_ratio=decrease,pad=%2:(ow-iw)/2:(oh-ih)/2,"
                                "setsar=1,fps=%3,format=yuv420p,setpts=PTS-STARTPTS[v%1];")
                     .arg(i).arg(size).arg(fps);
        inputs += QStringLiteral("[v%1]").arg(i);
        if (!audio)
            continue;
        QString source = QStringLiteral("[%1:a:0]").arg(i);
        if (!c.hasAudio) {
            args << "-f" << "lavfi" << "-t" << secs(c.end - c.start) << "-i" << "anullsrc=r=48000:cl=stereo";
            source = QStringLiteral("[%1:a]").arg(silence++);
        }
        // Padded to the clip length, otherwise a short audio track shifts all later clips.
        graph += source + STEREO + QStringLiteral(",asetpts=PTS-STARTPTS,apad=whole_dur=%1[a%2];")
                                       .arg(secs(c.end - c.start)).arg(i);
        inputs += QStringLiteral("[a%1]").arg(i);
    }
    graph += inputs + QStringLiteral("concat=n=%1:v=1:a=%2[v]").arg(clips.size()).arg(audio ? 1 : 0);
    // Music only with audio (not in pass 1); it comes after the silence inputs.
    double duration = 0;
    for (const Clip &c : clips)
        duration += c.end - c.start;
    const QList<Music> songs = audible(music, duration);
    if (audio && !songs.isEmpty()) {
        graph += "[ca];";
        QStringList labels = {"[ca]"};
        for (qsizetype i = 0; i < songs.size(); ++i) {
            addMusicInput(args, songs[i], duration);
            graph += musicFilter(silence + i, i, songs[i]);
            labels << QStringLiteral("[m%1]").arg(i);
        }
        graph += mixFilter(labels);
    } else if (audio) {
        graph += "[a]";
    }

    args << "-filter_complex" << graph << "-map" << "[v]";
    if (audio)
        args << "-map" << "[a]";
    args << "-c:v" << "libx264" << videoArgs;
    if (audio)
        args << "-c:a" << "aac" << "-b:a" << QString::number(audioKbps) + "k";
    if (output.isEmpty()) {
#ifdef Q_OS_WIN
        args << "-f" << "mp4" << "NUL";
#else
        args << "-f" << "mp4" << "/dev/null";
#endif
    } else {
        args << "-movflags" << "+faststart" << output;
    }
    return args;
}

static bool anyAudio(const QList<Clip> &clips)
{
    return std::any_of(clips.begin(), clips.end(), [](const Clip &c) { return c.hasAudio; });
}

QStringList concatOriginalArgs(const QList<Clip> &clips, int width, int height, double fps,
                               const QString &output, const QList<Music> &music)
{
    return concatEncodeArgs(clips, width, height, fps, {"-crf", "18", "-preset", "medium"},
                            anyAudio(clips) || !music.isEmpty() ? 192 : 0, output, music);
}

QStringList concatDiscordArgs(const QList<Clip> &clips, int width, int height, int pass,
                              const QString &passlog, const QString &output, const QList<Music> &music)
{
    double duration = 0;
    for (const Clip &c : clips)
        duration += c.end - c.start;
    const bool audio = anyAudio(clips) || !music.isEmpty();
    const double fit = std::min({1.0, 1920.0 / std::max(width, 1), 1080.0 / std::max(height, 1)});
    const QStringList videoArgs = {"-b:v", QString::number(discordVideoKbps(duration, audio)) + "k",
                                   "-passlogfile", passlog, "-pass", QString::number(pass)};
    return concatEncodeArgs(clips, int(width * fit), int(height * fit), 30, videoArgs,
                            pass == 2 && audio ? AUDIO_KBPS : 0, pass == 2 ? output : QString(), music);
}
