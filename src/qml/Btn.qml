import QtQuick
import QtQuick.Controls.Basic

// Button in the Retry styles: tab, tabDanger, ghost, primary, secondary, danger.
AbstractButton {
    id: b
    property string variant: "tab"
    /// tab: current page; secondary/danger: chosen by keyboard.
    property bool active: false
    property string iconName
    property real iconSize: 16
    property color iconColor: fg
    property real fontSize: 14
    property string tip
    property bool tipBelow: true

    readonly property bool hot: enabled && (hovered || pressed)
    readonly property color fg: {
        switch (variant) {
        case "tab": return !enabled ? Theme.txOff : (hot || active) ? Theme.tx : Theme.tx2
        case "tabDanger": return !enabled ? Theme.txOff : hot ? Theme.err : Theme.tx2
        case "ghost": return hot ? Theme.tx : Theme.tx2
        case "primary": return enabled ? "white" : Theme.tx3
        case "danger": return Theme.err
        default: return Theme.tx
        }
    }

    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    font.pixelSize: fontSize

    background: Rectangle {
        radius: Theme.r1
        color: {
            switch (b.variant) {
            case "tab": return (b.hot || b.active) && b.enabled ? Theme.sf : "transparent"
            case "tabDanger": return b.hot ? Theme.sf : "transparent"
            case "ghost": return b.hot ? Theme.sf2 : "transparent"
            case "primary": return !b.enabled ? Theme.sf2 : b.hovered ? Theme.aHi : Theme.aFill
            case "secondary": return b.hot || b.active ? Theme.sf3 : Theme.sf2
            case "danger": return Qt.alpha(Theme.err, b.hot || b.active ? 0.28 : 0.16)
            }
            return "transparent"
        }
        border.width: b.variant === "secondary" || b.variant === "danger" ? (b.active ? 2 : 1) : 0
        border.color: {
            if (b.variant === "danger")
                return b.active ? Theme.err : Qt.alpha(Theme.err, 0.5)
            return b.active ? Theme.tx2 : b.hot ? Theme.lnStrong : Theme.ln
        }
    }

    contentItem: Row {
        spacing: 8
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: b.iconName !== ""
            name: b.iconName
            size: b.iconSize
            color: b.iconColor
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: b.text !== ""
            text: b.text
            font: b.font
            color: b.fg
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    Tip {
        text: b.tip
        visible: b.tip !== "" && b.hovered
        below: b.tipBelow
    }
}
