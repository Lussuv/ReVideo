#include "files.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <algorithm>

#ifdef Q_OS_LINUX
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#endif

const QStringList &videoExtensions()
{
    static const QStringList exts = {"mp4", "mkv", "mov", "avi",  "webm", "flv",
                                     "wmv", "m4v", "mpg", "mpeg", "ts",   "3gp"};
    return exts;
}

const QStringList &audioExtensions()
{
    static const QStringList exts = {"mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma"};
    return exts;
}

bool isVideoFile(const QString &path)
{
    return videoExtensions().contains(QFileInfo(path).suffix().toLower());
}

bool isAudioFile(const QString &path)
{
    return audioExtensions().contains(QFileInfo(path).suffix().toLower());
}

QString launchFile(const QStringList &args)
{
    for (const QString &arg : args.mid(1)) {
        if (QFileInfo(arg).isFile() && (isVideoFile(arg) || isAudioFile(arg)))
            return QFileInfo(arg).absoluteFilePath();
    }
    return {};
}

QString canonical(const QString &path)
{
    const QString c = QFileInfo(path).canonicalFilePath();
    return c.isEmpty() ? QFileInfo(path).absoluteFilePath() : c;
}

QString adjacentMedia(const QString &current, int direction, const QSet<QString> &excluded)
{
    const QFileInfo cur(current);
    const auto sameKind = isAudioFile(current) ? isAudioFile : isVideoFile;
    QFileInfoList videos;
    for (const QFileInfo &fi : cur.dir().entryInfoList(QDir::Files))
        if (sameKind(fi.fileName()))
            videos.append(fi);
    std::sort(videos.begin(), videos.end(), [](const QFileInfo &a, const QFileInfo &b) {
        return a.fileName().toLower() < b.fileName().toLower();
    });

    const QString self = canonical(current);
    const auto it = std::find_if(videos.begin(), videos.end(),
                                 [&](const QFileInfo &fi) { return canonical(fi.filePath()) == self; });
    if (it == videos.end())
        return {};
    const qsizetype index = it - videos.begin(), len = videos.size();
    for (qsizetype offset = 1; offset < len; ++offset) {
        const qsizetype i = direction < 0 ? (index + len - offset) % len : (index + offset) % len;
        if (!excluded.contains(canonical(videos[i].filePath())))
            return videos[i].filePath();
    }
    return {};
}

bool inFlatpak()
{
    return QFile::exists(QStringLiteral("/.flatpak-info"));
}

#ifdef Q_OS_LINUX
/// Inside the sandbox XDG_DATA_HOME points into ~/.var/app, so QFile::moveToTrash
/// would hide files in a private trash; the portal uses the real one.
static QString portalTrash(const QString &path)
{
    // The portal only trashes files the sandbox could write itself, proven by the fd.
    QFile file(path);
    if (!file.open(QIODevice::ReadWrite | QIODevice::ExistingOnly))
        return file.errorString();
    auto msg = QDBusMessage::createMethodCall(
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Trash", "TrashFile");
    msg << QVariant::fromValue(QDBusUnixFileDescriptor(file.handle()));
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg);
    if (reply.type() == QDBusMessage::ErrorMessage)
        return reply.errorMessage();
    // The portal gives no reason; besides missing write access it refuses a trash
    // directory that is not mode 700 (seen with KDE-created ones).
    return reply.arguments().value(0).toUInt() == 1
               ? QString()
               : QStringLiteral("Portal hat abgelehnt. Falls das immer passiert: "
                                "chmod 700 ~/.local/share/Trash ~/.local/share/Trash/files "
                                "~/.local/share/Trash/info");
}
#endif

QString moveToTrash(const QString &path)
{
    QString error;
#ifdef Q_OS_LINUX
    if (inFlatpak())
        error = portalTrash(path);
    else
#endif
    {
        QFile file(path);
        if (!file.moveToTrash())
            error = file.errorString();
    }
    return error.isEmpty() ? QString() : QStringLiteral("Papierkorb fehlgeschlagen: %1").arg(error);
}

QString toolPath(const QString &name)
{
#ifdef Q_OS_WIN
    const QString file = name + ".exe";
#else
    const QString file = name;
#endif
    const QString bundled = QDir(QCoreApplication::applicationDirPath()).filePath(file);
    return QFileInfo(bundled).isFile() ? bundled : file;
}

QString tempSubdir(const QString &name)
{
    const QString dir = QDir::temp().filePath(QStringLiteral("revideo/") + name);
    QDir().mkpath(dir);
    return dir;
}

void prepareTool(QProcess &proc)
{
#ifdef Q_OS_WIN
    proc.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) {
        args->flags |= 0x08000000; // CREATE_NO_WINDOW
    });
#else
    Q_UNUSED(proc)
#endif
}

QString shortHash(const QString &text)
{
    return QString::fromLatin1(QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha256).toHex().left(16));
}
