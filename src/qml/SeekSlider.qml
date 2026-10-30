import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: s
    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    padding: 0
    implicitHeight: 16

    HoverHandler { cursorShape: s.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor }

    background: Rectangle {
        x: s.leftPadding
        y: s.topPadding + (s.availableHeight - height) / 2
        width: s.availableWidth
        height: 4
        radius: 2
        color: Theme.sf3

        Rectangle {
            width: s.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.aFill
        }
    }

    handle: Rectangle {
        readonly property real r: s.hovered || s.pressed ? 7 : 5
        x: s.leftPadding + s.visualPosition * s.availableWidth - r
        y: s.topPadding + (s.availableHeight - height) / 2
        width: 2 * r
        height: 2 * r
        radius: r
        color: Theme.tx
    }
}
