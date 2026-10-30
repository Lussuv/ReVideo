#include "exportjob.h"
#include "files.h"
#include "format.h"
#include "settings.h"
#include "version.h"

#include <QFile>
#include <QProcess>
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
        for (const char *name : {"a.mp4", "b.MKV", "c.txt", "d.webm"}) {
            QFile f(dir.filePath(name));
            QVERIFY(f.open(QIODevice::WriteOnly));
        }
        const QString a = dir.filePath("a.mp4");
        QCOMPARE(adjacentVideo(a, 1, {}), dir.filePath("b.MKV"));
        QCOMPARE(adjacentVideo(a, -1, {}), dir.filePath("d.webm"));
        QCOMPARE(adjacentVideo(a, 1, {canonical(dir.filePath("b.MKV"))}), dir.filePath("d.webm"));
        QCOMPARE(adjacentVideo(dir.filePath("d.webm"), 1, {}), a);
    }

    void launchFileTakesFirstVideo()
    {
        QTemporaryDir dir;
        QFile f(dir.filePath("clip.mkv"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        QCOMPARE(launchFile({"revideo", dir.filePath("missing.mp4"), f.fileName()}), f.fileName());
        QCOMPARE(launchFile({"revideo"}), QString());
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

        const QString thumb = dir.filePath("t.jpg");
        QCOMPARE(QProcess::execute("ffmpeg", thumbnailArgs(src, 6, thumb, true)), 0);
        QVERIFY(QFile::exists(thumb));
    }
};

QTEST_GUILESS_MAIN(CoreTest)
#include "tst_core.moc"
