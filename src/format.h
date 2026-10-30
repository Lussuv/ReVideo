#pragma once

#include <QString>
#include <optional>

QString formatTime(double sec, bool withMs);
/// Accepts HH:MM:SS, HH:MM:SS.mmm, MM:SS, MM:SS.mmm or raw seconds.
std::optional<double> parseTime(const QString &input);
QString formatBytes(qint64 bytes);
QString aspectRatio(int w, int h);
/// Rounds to the start of the nearest frame; cuts between frames would
/// leave a shortened (broken) frame at the edge of an export.
double snapToFrame(double sec, double frame);
/// Smallest "round" step that keeps timeline tick labels at least `gap` px apart.
double tickStep(double duration, double width, double gap);
