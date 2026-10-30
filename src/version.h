#pragma once

#include <QString>

/// Numeric "x.y.z" comparison; anything unparsable (pre-releases) is never newer.
bool isNewer(const QString &candidate, const QString &current);
