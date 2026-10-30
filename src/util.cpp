#include "util.h"

#include "files.h"
#include "format.h"
#include "settings.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>

Util::Util(QObject *parent) : QObject(parent)
{
    const Settings s = loadSettings();
    m_volume = s.volume;
    m_muted = s.muted;
}

QString Util::launchFile() const
{
    return ::launchFile(QCoreApplication::arguments());
}

QStringList Util::videoExtensions() const
{
    return ::videoExtensions();
}

QString Util::formatTime(double sec, bool withMs) const
{
    return ::formatTime(sec, withMs);
}

double Util::parseTime(const QString &input) const
{
    return ::parseTime(input).value_or(-1);
}

QString Util::formatBytes(double bytes) const
{
    return ::formatBytes(qint64(bytes));
}

QString Util::aspectRatio(int w, int h) const
{
    return ::aspectRatio(w, h);
}

double Util::snapToFrame(double sec, double frame) const
{
    return ::snapToFrame(sec, frame);
}

double Util::tickStep(double duration, double width, double gap) const
{
    return ::tickStep(duration, width, gap);
}

QString Util::adjacentVideo(const QString &path, int direction, bool skipSelf) const
{
    QSet<QString> excluded;
    if (skipSelf)
        excluded.insert(canonical(path));
    return ::adjacentVideo(path, direction, excluded);
}

QString Util::moveToTrash(const QString &path) const
{
    return ::moveToTrash(path);
}

double Util::fileSize(const QString &path) const
{
    return double(QFileInfo(path).size());
}

QString Util::fileName(const QString &path) const
{
    return QFileInfo(path).fileName();
}

QString Util::baseName(const QString &path) const
{
    return QFileInfo(path).completeBaseName();
}

QString Util::suffix(const QString &path) const
{
    return QFileInfo(path).suffix().toLower();
}

QUrl Util::folderUrl(const QString &path) const
{
    return QUrl::fromLocalFile(QFileInfo(path).absolutePath());
}

QUrl Util::siblingUrl(const QString &path, const QString &name) const
{
    return QUrl::fromLocalFile(QFileInfo(path).dir().filePath(name));
}

QString Util::urlToPath(const QUrl &url) const
{
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
}

void Util::saveSettings(double volume, bool muted)
{
    ::saveSettings({volume, muted});
}
