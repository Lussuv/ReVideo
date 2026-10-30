#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QtQmlIntegration>

/// Checks the public releases repo for a newer version and installs it:
/// Windows runs the installer silently, Flatpak installs the bundle on the
/// host; everything else opens the release page.
class Updater : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString version READ version NOTIFY changed)
    /// False: the button only opens the release page.
    Q_PROPERTY(bool canInstall READ canInstall NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)

public:
    using QObject::QObject;

    bool available() const { return !m_version.isEmpty(); }
    QString version() const { return m_version; }
    bool canInstall() const { return !m_url.isEmpty(); }
    bool busy() const { return m_busy; }

    /// Offline or API errors count as "no update".
    Q_INVOKABLE void check();
    Q_INVOKABLE void install();

signals:
    void changed();
    void error(const QString &message);

private:
    void installDownloaded(const QString &file);
    void fail(const QString &message);

    QNetworkAccessManager m_net;
    QString m_version;
    QString m_page;
    QString m_url;
    QString m_sha256;
    bool m_busy = false;
};
