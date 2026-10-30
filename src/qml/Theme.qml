pragma Singleton
import QtQuick

// Retry-Design 4.0 tokens.
QtObject {
    readonly property color bg: "#14161C"
    readonly property color bg2: "#1C1F27"
    readonly property color sf: "#272B36"
    readonly property color sf2: "#363C4A"
    readonly property color sf3: "#474E60"
    readonly property color sf4: "#596177"

    readonly property color lnSoft: Qt.rgba(1, 1, 1, 0.12)
    readonly property color ln: Qt.rgba(1, 1, 1, 0.18)
    readonly property color lnStrong: Qt.rgba(1, 1, 1, 0.30)

    readonly property color aFill: "#0E7A3C"
    readonly property color aHi: "#0F8241"
    readonly property color aText: "#45D67C"
    readonly property color aRing: Qt.rgba(48 / 255, 209 / 255, 88 / 255, 0.42)

    readonly property color tx: "#F2F3F7"
    readonly property color tx2: "#A8ACBA"
    readonly property color tx3: "#9398A8"
    readonly property color txOff: Qt.rgba(0x93 / 255, 0x98 / 255, 0xA8 / 255, 0.55)

    readonly property color err: "#FF6961"
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.32)

    readonly property real r1: 8
    readonly property real r2: 12
    readonly property real r4: 22

    readonly property string mono: "JetBrains Mono"
}
