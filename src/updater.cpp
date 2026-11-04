#include "updater.h"

#include "files.h"
#include "version.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QProcess>

/// Repo holding the release files the app updates from.
static const char LATEST[] = "https://api.github.com/repos/Lussuv/ReVideo-releases/releases/latest";

static QNetworkRequest request(const QUrl &url)
{
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, "ReVideo");
    return req;
}

void Updater::check()
{
    QNetworkReply *reply = m_net.get(request(QUrl(LATEST)));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "Update-Prüfung fehlgeschlagen:" << reply->errorString();
            return;
        }
        const QJsonObject release = QJsonDocument::fromJson(reply->readAll()).object();
        QString version = release.value("tag_name").toString();
        if (version.startsWith('v'))
            version.remove(0, 1);
        if (!isNewer(version, QCoreApplication::applicationVersion()))
            return;

#ifdef Q_OS_WIN
        const QString suffix = "-setup.exe";
#else
        const QString suffix = inFlatpak() ? ".flatpak" : QString();
#endif
        for (const QJsonValue &v : release.value("assets").toArray()) {
            const QJsonObject asset = v.toObject();
            // "sha256:<hex>", computed by GitHub on upload.
            const QString digest = asset.value("digest").toString();
            if (!suffix.isEmpty() && asset.value("name").toString().endsWith(suffix)
                && digest.startsWith("sha256:")) {
                m_url = asset.value("browser_download_url").toString();
                m_sha256 = digest.mid(7).toLower();
                break;
            }
        }
        m_version = version;
        m_page = release.value("html_url").toString();
        emit changed();
    });
}

void Updater::install()
{
    if (!available() || m_busy)
        return;
    if (!canInstall()) {
        if (!QDesktopServices::openUrl(QUrl(m_page)))
            emit error(QStringLiteral("Browser konnte nicht geöffnet werden"));
        return;
    }
    m_busy = true;
    emit changed();

    // In Flatpak the host's flatpak has to read the bundle: the sandbox's /tmp is
    // private, XDG_CACHE_HOME (~/.var/app/<id>/cache) has the same path on both sides.
#ifdef Q_OS_WIN
    const QString file = QDir(tempSubdir("update")).filePath("ReVideo-setup.exe");
#else
    const QString file = QDir(qEnvironmentVariable("XDG_CACHE_HOME", QDir::tempPath()))
                             .filePath("ReVideo-update.flatpak");
#endif
    auto out = std::make_shared<QFile>(file);
    if (!out->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        fail(QStringLiteral("Update-Download fehlgeschlagen: %1").arg(out->errorString()));
        return;
    }
    auto hash = std::make_shared<QCryptographicHash>(QCryptographicHash::Sha256);
    QNetworkReply *reply = m_net.get(request(QUrl(m_url)));
    connect(reply, &QNetworkReply::readyRead, this, [=] {
        const QByteArray chunk = reply->readAll();
        hash->addData(chunk);
        out->write(chunk);
    });
    connect(reply, &QNetworkReply::finished, this, [=, this] {
        reply->deleteLater();
        const QByteArray rest = reply->readAll();
        hash->addData(rest);
        out->write(rest);
        out->close();
        if (reply->error() != QNetworkReply::NoError) {
            QFile::remove(file);
            fail(QStringLiteral("Update-Download fehlgeschlagen: %1").arg(reply->errorString()));
        } else if (QString::fromLatin1(hash->result().toHex()) != m_sha256) {
            QFile::remove(file);
            fail(QStringLiteral("Update verworfen: Prüfsumme stimmt nicht."));
        } else {
            installDownloaded(file);
        }
    });
}

void Updater::installDownloaded(const QString &file)
{
#ifdef Q_OS_WIN
    // The installer waits for this process to exit and starts the new version.
    if (!QProcess::startDetached(file, {"/S"})) {
        fail(QStringLiteral("Installer konnte nicht gestartet werden"));
        return;
    }
    QCoreApplication::quit();
#else
    // Needs --talk-name=org.freedesktop.Flatpak. Installs into the installation this
    // instance runs from, otherwise the old one stays in use.
    QFile info("/.flatpak-info");
    const bool user = info.open(QIODevice::ReadOnly)
                      && QString::fromUtf8(info.readAll()).contains("/.local/share/flatpak/app/");
    auto *proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [=, this](int code, QProcess::ExitStatus status) {
        proc->deleteLater();
        QFile::remove(file);
        if (status != QProcess::NormalExit || code != 0) {
            fail(QStringLiteral("Update-Installation fehlgeschlagen: %1")
                     .arg(QString::fromUtf8(proc->readAllStandardError()).trimmed()));
            return;
        }
        const QString id = qEnvironmentVariable("FLATPAK_ID", "de.retrydev.ReVideo");
        if (!QProcess::startDetached("flatpak-spawn", {"--host", "flatpak", "run", id})) {
            fail(QStringLiteral("Neue Version konnte nicht gestartet werden"));
            return;
        }
        QCoreApplication::quit();
    });
    connect(proc, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            proc->deleteLater();
            fail(QStringLiteral("Flatpak konnte nicht gestartet werden: %1").arg(proc->errorString()));
        }
    });
    // No --noninteractive: it also forbids polkit's password prompt, which a system
    // installation needs ("InstallBundle not allowed for user"). -y answers the rest.
    proc->start("flatpak-spawn", {"--host", "flatpak", "install", user ? "--user" : "--system",
                                  "-y", "--bundle", file});
#endif
}

void Updater::fail(const QString &message)
{
    m_busy = false;
    emit changed();
    emit error(message);
}
