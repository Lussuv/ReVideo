#include <QFontDatabase>
#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <clocale>

int main(int argc, char *argv[])
{
    // libmpv renders through OpenGL only.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QQuickStyle::setStyle("Basic");

    // QApplication, not QGuiApplication: KDE only hands out its native file
    // dialog (widget based) to widget applications, otherwise Qt uses its QML fallback.
    QApplication app(argc, argv);
    QGuiApplication::setApplicationName("ReVideo");
    QGuiApplication::setApplicationVersion(APP_VERSION);
    QGuiApplication::setOrganizationName("Retry");
    QGuiApplication::setDesktopFileName("de.retrydev.ReVideo");
    QGuiApplication::setWindowIcon(QIcon(":/assets/icon-128.png"));
    // mpv parses numbers with the C locale; Qt applies the user's locale on startup.
    std::setlocale(LC_NUMERIC, "C");

    for (const char *font : {"Inter-Regular", "Inter-SemiBold", "JetBrainsMono-Regular"})
        QFontDatabase::addApplicationFont(QStringLiteral(":/assets/fonts/%1.ttf").arg(font));
    QGuiApplication::setFont(QFont("Inter"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("ReVideo", "Main");
    return QGuiApplication::exec();
}
