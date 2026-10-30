#include "settings.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtDebug>

QString settingsFile()
{
#ifdef Q_OS_WIN
    const QString dir = QDir(qEnvironmentVariable("APPDATA")).filePath("ReVideo");
#else
    QString base = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (base.isEmpty())
        base = QDir(qEnvironmentVariable("HOME")).filePath(".config");
    const QString dir = QDir(base).filePath("revideo");
#endif
    return QDir(dir).filePath("settings.json");
}

Settings loadSettings(const QString &file)
{
    Settings s;
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return s;
    const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
    s.volume = obj.value("volume").toDouble(s.volume);
    s.muted = obj.value("muted").toBool(s.muted);
    return s;
}

void saveSettings(const Settings &settings, const QString &file)
{
    QDir().mkpath(QFileInfo(file).absolutePath());
    QFile f(file);
    const QJsonObject obj{{"volume", settings.volume}, {"muted", settings.muted}};
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)
        || f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact)) < 0)
        qWarning() << "Einstellungen nicht gespeichert:" << f.errorString();
}
