#pragma once

#include <QObject>
#include <QStringList>
#include <QtQmlIntegration>
#include <functional>

class QProcess;

/// Runs the ffmpeg export for the trim range and reports its progress.
class Exporter : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(double percent READ percent NOTIFY progressChanged)
    Q_PROPERTY(QString speed READ speed NOTIFY progressChanged)
    Q_PROPERTY(double eta READ eta NOTIFY progressChanged)

public:
    using QObject::QObject;

    bool running() const { return m_proc != nullptr; }
    double percent() const { return m_percent; }
    QString speed() const { return m_speed; }
    double eta() const { return m_eta; }

    /// `preset`: 0 = Original, 1 = Discord.
    Q_INVOKABLE void start(const QString &input, const QString &output, double start, double end,
                           int preset, bool hasAudio);

    /// Writes the frame shown at `frameStart` (a snapped frame time) as PNG.
    Q_INVOKABLE void saveFrame(const QString &input, double frameStart, double frameDuration,
                               const QString &output);

signals:
    void frameSaved(const QString &error);
    void runningChanged();
    void progressChanged();
    /// Empty `error` on success.
    void finished(const QString &error);

private:
    /// Runs one ffmpeg pass whose progress covers `offset..offset+scale` %.
    void run(const QStringList &args, double offset, double scale, std::function<void()> next);
    void finish(const QString &error);

    QProcess *m_proc = nullptr;
    qint64 m_durationUs = 0;
    double m_percent = 0;
    QString m_speed;
    double m_eta = 0;
};
