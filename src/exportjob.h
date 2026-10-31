#pragma once

#include <QString>
#include <QStringList>

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
