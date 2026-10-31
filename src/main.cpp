#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QIcon>
#include <QMessageBox>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <clocale>
#include <cstdio>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {

QFile *logFile = nullptr;

/// A Windows GUI app has no console, so Qt's and mpv's messages would be lost;
/// they also go to a log file that every start overwrites.
void logMessage(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    const QByteArray line = qFormatLogMessage(type, context, message).toUtf8() + '\n';
    std::fputs(line.constData(), stderr);
    if (logFile) {
        logFile->write(line);
        logFile->flush();
    }
#ifdef Q_OS_WIN
    // qFatal ends the process right after this; without a console nobody would see why.
    if (type == QtFatalMsg)
        MessageBoxW(nullptr, reinterpret_cast<const wchar_t *>(message.utf16()), L"ReVideo",
                    MB_ICONERROR);
#endif
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication::setApplicationName("ReVideo");
    QCoreApplication::setApplicationVersion(APP_VERSION);
    QCoreApplication::setOrganizationName("Retry");

    const QString logDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(logDir);
    const QString logPath = QDir(logDir).filePath("revideo.log");
    QFile log(logPath);
    if (log.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        logFile = &log;
    qSetMessagePattern("%{time hh:mm:ss.zzz} %{type} %{if-category}%{category}: %{endif}%{message}");
    qInstallMessageHandler(logMessage);

    // libmpv renders through OpenGL only.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickStyle::setStyle("Basic");

    // QApplication, not QGuiApplication: KDE only hands out its native file
    // dialog (widget based) to widget applications, otherwise Qt uses its QML fallback.
    QApplication app(argc, argv);
    QGuiApplication::setDesktopFileName("de.retrydev.ReVideo");
    QGuiApplication::setWindowIcon(QIcon(":/assets/icon-128.png"));
    // mpv parses numbers with the C locale; Qt applies the user's locale on startup.
    std::setlocale(LC_NUMERIC, "C");
    qInfo("ReVideo %s, Qt %s, %s", APP_VERSION, qVersion(), qPrintable(QSysInfo::prettyProductName()));

    for (const char *font : {"Inter-Regular", "Inter-SemiBold", "JetBrainsMono-Regular"})
        QFontDatabase::addApplicationFont(QStringLiteral(":/assets/fonts/%1.ttf").arg(font));
    QGuiApplication::setFont(QFont("Inter"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [logPath] {
            QMessageBox::critical(nullptr, "ReVideo",
                                  QStringLiteral("Die Oberfläche konnte nicht geladen werden.\n\n"
                                                 "Details stehen in:\n%1")
                                      .arg(QDir::toNativeSeparators(logPath)));
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.loadFromModule("ReVideo", "Main");
    const int code = QGuiApplication::exec();
    logFile = nullptr;
    return code;
}
