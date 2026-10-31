#include "exportjob.h"
#include "files.h"
#include "format.h"
#include "settings.h"
#include "version.h"

#include <QFile>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

class CoreTest : public QObject {
    Q_OBJECT

private slots:
    void timeRoundtrip()
    {
        QCOMPARE(formatTime(3725.5, true), "01:02:05.500");
        QCOMPARE(formatTime(qQNaN(), false), "00:00:00");
        QCOMPARE(parseTime("01:02:05.5"), 3725.5);
        QCOMPARE(parseTime("2:05"), 125.0);
        QCOMPARE(parseTime("12.25"), 12.25);
        QVERIFY(!parseTime("1:75"));
        QVERIFY(!parseTime("abc"));
        QVERIFY(!parseTime("1:02.1234"));
    }

    void bytesAndAspect()
    {
        QCOMPARE(formatBytes(1536), "1.50 KB");
        QCOMPARE(formatBytes(512), "512 B");
        QCOMPARE(aspectRatio(1920, 1080), "16:9");
    }

    void snapsToNearestFrameStart()
    {
        const double frame = 1.0 / 30;
        QVERIFY(qAbs(snapToFrame(0.222, frame) - 7 * frame) < 1e-9);
        QVERIFY(qAbs(snapToFrame(0.856, frame) - 26 * frame) < 1e-9);
        QCOMPARE(snapToFrame(0, frame), 0.0);
        const double ntsc = 1001.0 / 30000;
        QVERIFY(qAbs(snapToFrame(10, ntsc) - 300 * ntsc) < 1e-9);
    }

    void tickSteps()
    {
        QCOMPARE(tickStep(60, 900, 90), 10.0);
        QCOMPARE(tickStep(100000, 100, 90), 7200.0);
    }

    void comparesVersionsNumerically()
    {
        QVERIFY(isNewer("3.1.1", "3.1.0"));
        QVERIFY(isNewer("3.10.0", "3.9.0"));
        QVERIFY(isNewer("4.0.0", "3.99.99"));
        QVERIFY(!isNewer("3.1.0", "3.1.0"));
        QVERIFY(!isNewer("3.0.9", "3.1.0"));
        QVERIFY(!isNewer("3.2.0-beta", "3.1.0"));
    }

    void adjacentWrapsAndSkipsExcluded()
    {
        QTemporaryDir dir;
        for (const char *name : {"a.mp4", "b.MKV", "c.txt", "d.webm", "e.mp3", "f.FLAC"}) {
            QFile f(dir.filePath(name));
            QVERIFY(f.open(QIODevice::WriteOnly));
        }
        const QString a = dir.filePath("a.mp4");
        QCOMPARE(adjacentMedia(a, 1, {}), dir.filePath("b.MKV"));
        QCOMPARE(adjacentMedia(a, -1, {}), dir.filePath("d.webm"));
        QCOMPARE(adjacentMedia(a, 1, {canonical(dir.filePath("b.MKV"))}), dir.filePath("d.webm"));
        // Videos and songs stay apart.
        QCOMPARE(adjacentMedia(dir.filePath("d.webm"), 1, {}), a);
        QCOMPARE(adjacentMedia(dir.filePath("e.mp3"), 1, {}), dir.filePath("f.FLAC"));
        QCOMPARE(adjacentMedia(dir.filePath("f.FLAC"), 1, {}), dir.filePath("e.mp3"));
    }

    void launchFileTakesFirstVideo()
    {
        QTemporaryDir dir;
        QFile f(dir.filePath("clip.mkv"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QCOMPARE(launchFile({"revideo", dir.filePath("missing.mp4"), f.fileName()}), f.fileName());
        QCOMPARE(launchFile({"revideo"}), QString());
        QFile song(dir.filePath("song.mp3"));
        QVERIFY(song.open(QIODevice::WriteOnly));
        QCOMPARE(launchFile({"revideo", song.fileName()}), song.fileName());
    }

    void twoPassProgressMapping()
    {
        QCOMPARE(progressFor(500000, "1x", 1000000, 0, 50).percent, 25.0);
        QCOMPARE(progressFor(500000, "1x", 1000000, 50, 50).percent, 75.0);
        QCOMPARE(progressFor(2000000, "2x", 1000000, 50, 50).percent, 99.5);
        QCOMPARE(progressFor(0, "2x", 4000000, 0, 100).etaSec, 2.0);
    }

    void settingsRoundtripAndDefaults()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("sub/settings.json");
        QCOMPARE(loadSettings(file).volume, 0.8);
        saveSettings({0.3, true}, file);
        const Settings s = loadSettings(file);
        QCOMPARE(s.volume, 0.3);
        QVERIFY(s.muted);

        // Files from older versions only carry the volume.
        QFile old(file);
        QVERIFY(old.open(QIODevice::WriteOnly | QIODevice::Truncate));
        old.write(R"({"volume":0.5})");
        old.close();
        QCOMPARE(loadSettings(file).volume, 0.5);
        QVERIFY(!loadSettings(file).muted);
    }

    void discordBitrateStaysUnderLimit()
    {
        const qint64 kbps = discordVideoKbps(60, true);
        QVERIFY((kbps + 96) * 1000 * 60 / 8 <= 9'300'000);
        QCOMPARE(discordVideoKbps(1e6, false), 50);
    }

    void parsesMediaInfo()
    {
        const QString log = R"(Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'a.mp4':
  Duration: 00:01:04.50, start: 0.000000, bitrate: 3226 kb/s
  Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(progressive), 1280x720 [SAR 1:1 DAR 16:9], 3145 kb/s, 29.97 fps, 29.97 tbr, 15360 tbn (default)
    Side data:
      Display Matrix: rotation of -90.00 degrees
  Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706D), 44100 Hz, mono, fltp, 69 kb/s (default)
  Stream #0:2: Video: mjpeg (Baseline), yuvj420p(pc), 320x180, 90k tbr (attached pic)
At least one output file must be specified)";
        const auto info = parseMediaInfo(log);
        QVERIFY(info);
        QCOMPARE(info->duration, 64.5);
        QCOMPARE(info->width, 720);
        QCOMPARE(info->height, 1280);
        QCOMPARE(info->fps, 29.97);
        QVERIFY(info->hasAudio);
        QCOMPARE(info->signature, "h264|yuv420p|1280x720|29.97 fps|-90.00|aac|44100 Hz|mono");

        QVERIFY(info->hasVideo);
        const auto song = parseMediaInfo("  Duration: 00:03:00.00, start: 0.000000\n"
                                         "  Stream #0:0: Audio: mp3, 44100 Hz, stereo, fltp, 128 kb/s");
        QVERIFY(song && !song->hasVideo && song->hasAudio);
        QCOMPARE(song->duration, 180.0);
        QVERIFY(!parseMediaInfo("At least one output file must be specified"));

        // Two buckets of two samples: peaks 1000 and 4000, scaled to the louder one.
        const qint16 pcm[] = {100, -1000, 4000, -20};
        QCOMPARE(waveformPeaks(QByteArray(reinterpret_cast<const char *>(pcm), sizeof pcm), 4, 2),
                 (QList<float>{0.25f, 1.0f}));
        QCOMPARE(concatList({{"/v/it's.mp4", 1, 2.5, true}}),
                 "ffconcat version 1.0\nfile '/v/it'\\''s.mp4'\ninpoint 1.000\noutpoint 2.500\n");
    }

    /// Joins clips with the real ffmpeg: lossless for equal clips, re-encoded for mixed ones.
    void concatProducesFiles()
    {
        if (QStandardPaths::findExecutable("ffmpeg").isEmpty())
            QSKIP("ffmpeg nicht gefunden");
        QTemporaryDir dir;
        const auto make = [&](const QString &name, const QString &size, bool audio) {
            QStringList args = {"-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=" + size + ":rate=30"};
            if (audio)
                args << "-f" << "lavfi" << "-i" << "sine" << "-c:a" << "aac";
            args << "-t" << "4" << "-c:v" << "libx264" << "-preset" << "ultrafast" << "-g" << "15" << dir.filePath(name);
            QCOMPARE(QProcess::execute("ffmpeg", args), 0);
        };
        make("a.mp4", "640x360", true);
        make("b.mp4", "640x360", true);
        make("c.mp4", "360x640", false);
        const auto probe = [&](const QString &name) {
            QProcess p;
            p.start("ffmpeg", probeArgs(dir.filePath(name)));
            p.waitForFinished();
            return parseMediaInfo(QString::fromUtf8(p.readAllStandardError())).value_or(MediaInfo{});
        };
        QCOMPARE(probe("a.mp4").signature, probe("b.mp4").signature);
        QVERIFY(probe("a.mp4").signature != probe("c.mp4").signature);

        const QList<Clip> same = {{dir.filePath("a.mp4"), 1, 3, true}, {dir.filePath("b.mp4"), 0, 2, true}};
        QFile list(dir.filePath("list.txt"));
        QVERIFY(list.open(QIODevice::WriteOnly));
        list.write(concatList(same).toUtf8());
        list.close();
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"} + concatCopyArgs(list.fileName(), dir.filePath("copy.mp4"))), 0);
        QVERIFY(qAbs(probe("copy.mp4").duration - 4) < 0.6);

        const QList<Clip> mixed = {{dir.filePath("a.mp4"), 1, 3, true}, {dir.filePath("c.mp4"), 0.5, 2, false}};
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"} + concatOriginalArgs(mixed, 640, 360, 30, dir.filePath("orig.mp4"))), 0);
        const MediaInfo orig = probe("orig.mp4");
        QVERIFY(qAbs(orig.duration - 3.5) < 0.1);
        QCOMPARE(orig.width, 640);
        QVERIFY(orig.hasAudio);

        const QString passlog = dir.filePath("p"), out = dir.filePath("discord.mp4");
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"} + concatDiscordArgs(mixed, 640, 360, 1, passlog, out)), 0);
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"} + concatDiscordArgs(mixed, 640, 360, 2, passlog, out)), 0);
        QVERIFY(qAbs(probe("discord.mp4").duration - 3.5) < 0.1);

        // Music: lossless video with mixed audio, and re-encoded clips without own audio.
        QCOMPARE(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=880",
                                              "-t", "10", "-c:a", "aac", dir.filePath("song.m4a")}),
                 0);
        const Music late{dir.filePath("song.m4a"), 1.5, 0.5};
        // Two pieces of one song, as after a cut: 1 s from 6 s at 0, the rest of it from 2.5 s.
        const QList<Music> pieces = {{dir.filePath("song.m4a"), 0, 1, 6, 1}, {dir.filePath("song.m4a"), 2.5, 1, 7, -1}};
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"}
                                                 + concatCopyArgs(list.fileName(), dir.filePath("music.mp4"), pieces, true, 4)),
                 0);
        const MediaInfo withMusic = probe("music.mp4");
        QVERIFY(withMusic.hasAudio && qAbs(withMusic.duration - 4) < 0.6);

        // The second clip muted: its two seconds are silent, the first clip's are not.
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"}
                                                 + concatCopyArgs(list.fileName(), dir.filePath("muted.mp4"), {}, true, 4,
                                                                  {{2, 4}})),
                 0);
        QProcess silence;
        silence.start("ffmpeg", {"-i", dir.filePath("muted.mp4"), "-af", "silencedetect=n=-50dB:d=1", "-f", "null", "-"});
        silence.waitForFinished();
        const QString detected = QString::fromUtf8(silence.readAllStandardError());
        const auto start = QRegularExpression(R"(silence_start: ([\d.]+))").match(detected);
        QVERIFY2(start.hasMatch() && qAbs(start.captured(1).toDouble() - 2) < 0.05, qPrintable(detected.right(400)));
        const Music early{dir.filePath("song.m4a"), -3, 1};
        const QList<Clip> silent = {{dir.filePath("c.mp4"), 0, 3, false}};
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"}
                                                 + concatOriginalArgs(silent, 360, 640, 30, dir.filePath("sm.mp4"), {early, late})),
                 0);
        const MediaInfo silentMusic = probe("sm.mp4");
        QVERIFY(silentMusic.hasAudio && qAbs(silentMusic.duration - 3) < 0.1);
        QCOMPARE(QProcess::execute("ffmpeg", QStringList{"-v", "error"}
                                                 + concatDiscordArgs(mixed, 640, 360, 2, passlog, out, {late})),
                 0);
        QVERIFY(qAbs(probe("discord.mp4").duration - 3.5) < 0.1);
    }

    /// Runs the real ffmpeg with both presets; skipped without ffmpeg/libx264 on PATH.
    void exportPresetsProduceFiles()
    {
        if (QStandardPaths::findExecutable("ffmpeg").isEmpty())
            QSKIP("ffmpeg nicht gefunden");
        QTemporaryDir dir;
        const QString src = dir.filePath("src.mp4");
        QCOMPARE(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-f", "lavfi", "-i",
                                              "testsrc2=size=1920x1080:rate=60", "-f", "lavfi",
                                              "-i", "sine", "-t", "12", "-c:v", "libx264", "-preset",
                                              "ultrafast", "-g", "30", "-c:a", "aac", src}),
                 0);

        QCOMPARE(QProcess::execute("ffmpeg", originalArgs(src, dir.filePath("orig.mp4"), 2, 8)), 0);
        const QString passlog = dir.filePath("p");
        const QString out = dir.filePath("discord.mp4");
        QCOMPARE(QProcess::execute("ffmpeg", discordArgs(src, out, 2, 8, true, 1, passlog)), 0);
        QCOMPARE(QProcess::execute("ffmpeg", discordArgs(src, out, 2, 8, true, 2, passlog)), 0);
        QVERIFY(QFileInfo(out).size() > 0 && QFileInfo(out).size() <= 10'000'000);

        const QList<Thumb> thumbs = {{2, dir.filePath("t1.jpg")}, {6, dir.filePath("t2.jpg")}};
        QProcess::execute("ffmpeg", thumbnailArgs(src, thumbs, true));
        QVERIFY(QFile::exists(thumbs[0].target) && QFile::exists(thumbs[1].target));
        // Past the last keyframe the fast path yields nothing; the slow one does.
        const QList<Thumb> late = {{11.9, dir.filePath("t3.jpg")}};
        QCOMPARE(QProcess::execute("ffmpeg", thumbnailArgs(src, late, false)), 0);
        QVERIFY(QFile::exists(late[0].target));
    }
};

QTEST_GUILESS_MAIN(CoreTest)
#include "tst_core.moc"
