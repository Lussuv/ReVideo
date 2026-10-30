#include "format.h"

#include <QStringList>
#include <cmath>
#include <numeric>

QString formatTime(double sec, bool withMs)
{
    if (!std::isfinite(sec) || sec < 0)
        sec = 0;
    const auto totalMs = static_cast<qint64>(std::floor(sec * 1000));
    const qint64 h = totalMs / 3600000, m = totalMs / 60000 % 60, s = totalMs / 1000 % 60,
                 ms = totalMs % 1000;
    return withMs ? QString::asprintf("%02lld:%02lld:%02lld.%03lld", h, m, s, ms)
                  : QString::asprintf("%02lld:%02lld:%02lld", h, m, s);
}

std::optional<double> parseTime(const QString &raw)
{
    const QString input = raw.trimmed();
    bool ok = false;
    const double plain = input.toDouble(&ok);
    if (ok)
        return plain >= 0 && std::isfinite(plain) ? std::optional(plain) : std::nullopt;

    QString clock = input;
    double ms = 0;
    if (const auto dot = input.indexOf('.'); dot >= 0) {
        const QString frac = input.mid(dot + 1);
        const bool digits = std::all_of(frac.begin(), frac.end(), [](QChar c) { return c.isDigit(); });
        if (frac.isEmpty() || frac.size() > 3 || !digits)
            return std::nullopt;
        clock = input.left(dot);
        ms = frac.leftJustified(3, '0').toInt() / 1000.0;
    }

    QList<qint64> parts;
    for (const QString &p : clock.split(':')) {
        const qint64 v = p.toLongLong(&ok);
        if (!ok || v < 0)
            return std::nullopt;
        parts.append(v);
    }
    qint64 h = 0, m, s;
    if (parts.size() == 2) {
        m = parts[0];
        s = parts[1];
    } else if (parts.size() == 3) {
        h = parts[0];
        m = parts[1];
        s = parts[2];
    } else {
        return std::nullopt;
    }
    if (m >= 60 || s >= 60)
        return std::nullopt;
    return double(h * 3600 + m * 60 + s) + ms;
}

QString formatBytes(qint64 bytes)
{
    if (bytes <= 0)
        return QStringLiteral("0 B");
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    const int i = std::min(4, int(std::floor(std::log(double(bytes)) / std::log(1024.0))));
    const double v = bytes / std::pow(1024.0, i);
    return QStringLiteral("%1 %2").arg(QString::number(v, 'f', i == 0 ? 0 : 2), units[i]);
}

QString aspectRatio(int w, int h)
{
    const int g = std::max(1, std::gcd(w, h));
    return QStringLiteral("%1:%2").arg(w / g).arg(h / g);
}

double snapToFrame(double sec, double frame)
{
    return std::round(sec / frame) * frame;
}

double tickStep(double duration, double width, double gap)
{
    static const double steps[] = {1,   2,   5,   10,  15,   30,   60,
                                   120, 300, 600, 900, 1800, 3600, 7200};
    const double pxPerSec = width / std::max(duration, 0.001);
    for (double step : steps)
        if (step * pxPerSec >= gap)
            return step;
    return 7200;
}
