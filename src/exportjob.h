#pragma once

#include <QString>
#include <QStringList>
#include <optional>

enum class Preset { Original = 0, Discord = 1 };

struct Progress {
    double percent = 0;
    QString speed;
    double etaSec = 0;
};

/// Maps one ffmpeg run's 0..100 % onto the slice `offset..offset+scale` (used for 2-pass).
Progress progressFor(qint64 outUs, const QString &speed, qint64 durationUs, double offset, double scale);

/// Stream-copy trim: keeps codecs and container, very fast, lossless. The start
/// snaps to the preceding keyframe (small inaccuracy).
QStringList originalArgs(const QString &input, const QString &output, double start, double duration);

/// Two-pass H.264 aiming at ≤ 10 MB, capped at 1080p / 30 fps. `output` is
/// ignored for pass 1, which writes to the null device.
QStringList discordArgs(const QString &input, const QString &output, double start, double duration,
                        bool hasAudio, int pass, const QString &passlog);
qint64 discordVideoKbps(double duration, bool hasAudio);

/// The frame at `ts` as PNG; input seeking is frame-exact when re-encoding.
QStringList frameArgs(const QString &input, double ts, const QString &output);

struct Thumb {
    double ts;
    QString target;
};
/// All `thumbs` from a single ffmpeg run, one input per thumbnail; a process per
/// thumbnail costs far more, above all on Windows. `fast` decodes only keyframes
/// and yields nothing for a slot without a keyframe at or after `ts`.
QStringList thumbnailArgs(const QString &input, const QList<Thumb> &thumbs, bool fast);

struct MediaInfo {
    double duration = 0;
    bool hasVideo = false;
    /// Displayed size, i.e. with the rotation applied.
    int width = 0;
    int height = 0;
    double fps = 0;
    bool hasAudio = false;
    /// Stream parameters that must be equal for a lossless join.
    QString signature;
};
/// `ffmpeg -i <input>` without an output; it only prints the stream details.
QStringList probeArgs(const QString &input);
/// Reads the stderr of probeArgs(); nullopt without any video or audio stream.
std::optional<MediaInfo> parseMediaInfo(const QString &log);

/// Mono 16-bit PCM at WAVEFORM_RATE of the input's audio on stdout, for waveformPeaks().
QStringList waveformArgs(const QString &input);
inline constexpr int WAVEFORM_RATE = 8000;
/// Loudest sample per 1/`perSecond` s, scaled so that the loudest bucket is 1.
QList<float> waveformPeaks(const QByteArray &pcm, int sampleRate, int perSecond);

struct Clip {
    QString path;
    double start;
    double end;
    bool hasAudio;
};
/// A piece of music under the joined clips: `length` seconds of the song from `start`
/// (negative length: to its end), placed at `offset` on the clips' timeline. Whatever lies
/// before or beyond the clips is cut off.
struct Music {
    QString path;
    double offset = 0;
    double volume = 1;
    double start = 0;
    double length = -1;
};

/// A stretch of the joined timeline, in seconds.
struct Span {
    double from;
    double to;
};

/// Concat demuxer script: every clip with its in and out point.
QString concatList(const QList<Clip> &clips);
/// Lossless join of the clips in `listFile` (see concatList()); needs equal signatures.
/// As with originalArgs(), each clip starts at the keyframe before its in point. With
/// music or `mutes` (muted clips) only the audio is re-encoded, mixed into the clips' own
/// if `clipAudio`.
QStringList concatCopyArgs(const QString &listFile, const QString &output, const QList<Music> &music = {},
                           bool clipAudio = true, double duration = 0, const QList<Span> &mutes = {});
/// Re-encodes the clips back to back as H.264 (CRF 18) at `width`×`height` and `fps`;
/// clips of another format are letterboxed, clips without audio get silence.
QStringList concatOriginalArgs(const QList<Clip> &clips, int width, int height, double fps,
                               const QString &output, const QList<Music> &music = {});
/// Like discordArgs() for joined clips: the first clip's size fitted into 1080p, 30 fps.
QStringList concatDiscordArgs(const QList<Clip> &clips, int width, int height, int pass,
                              const QString &passlog, const QString &output, const QList<Music> &music = {});
