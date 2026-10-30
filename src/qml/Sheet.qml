import QtQuick
import QtQuick.Effects

// Raised surface: popover, dialog, control bar, panel. `elevation` 1–3 as in Retry.
Rectangle {
    id: sheet
    property int elevation: 3

    color: Theme.sf2
    radius: Theme.r2
    border.color: Theme.ln
    border.width: 1

    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: sheet.radius
        offset.y: sheet.elevation === 1 ? 1 : sheet.elevation === 2 ? 6 : 16
        blur: sheet.elevation === 1 ? 3 : sheet.elevation === 2 ? 18 : 48
        color: Qt.rgba(0, 0, 0, sheet.elevation === 1 ? 0.30 : sheet.elevation === 2 ? 0.34 : 0.42)
    }
}
