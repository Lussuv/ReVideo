#include "version.h"

#include <QList>
#include <QStringList>
#include <optional>

static std::optional<QList<uint>> parse(const QString &v)
{
    QList<uint> parts;
    for (const QString &p : v.split('.')) {
        bool ok = false;
        parts.append(p.toUInt(&ok));
        if (!ok)
            return std::nullopt;
    }
    return parts;
}

bool isNewer(const QString &candidate, const QString &current)
{
    const auto c = parse(candidate), r = parse(current);
    return c && r && *c > *r;
}
