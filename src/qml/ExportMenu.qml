import QtQuick
import QtQuick.Controls.Basic

Sheet {
    id: menu
    required property var app
    readonly property var exporter: app.exporter

    width: col.width + 28
    height: col.implicitHeight + 28

    // Clicks inside must not reach the dismiss layer underneath.
    MouseArea { anchors.fill: parent }

    Column {
        id: col
        x: 14
        y: 14
        width: 340
        spacing: 6

        Text { text: "Export-Vorlage"; color: Theme.tx2; font.pixelSize: 13; font.weight: Font.DemiBold }
        PresetRow {
            preset: 0
            label: "Original"
            desc: "Quell-Codec & Container, verlustfreier Schnell-Trim"
        }
        PresetRow {
            preset: 1
            label: "Discord (≤ 10 MB)"
            desc: "Max. Qualität unter 10 MB • 1080p • 30 fps • 2-Pass"
        }

        Column {
            visible: menu.exporter.running
            width: parent.width
            spacing: 6

            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Theme.sf
                Rectangle {
                    width: parent.width * menu.exporter.percent / 100
                    height: parent.height
                    radius: 3
                    color: Theme.aFill
                }
            }
            Row {
                spacing: 12
                Meta { text: menu.exporter.percent.toFixed(0) + " %"; color: Theme.tx2 }
                Meta { text: menu.exporter.speed; visible: text !== "" }
                Meta {
                    text: "ETA " + Util.formatTime(menu.exporter.eta, false)
                    visible: menu.exporter.eta > 0
                }
            }
        }

        Btn {
            width: parent.width
            variant: "primary"
            iconName: "upload"
            text: menu.exporter.running ? "Exportiere …" : "Exportieren"
            enabled: !menu.exporter.running
            verticalPadding: 8
            horizontalPadding: 14
            onClicked: menu.app.startExport()
        }
    }

    component Meta: Text {
        color: Theme.tx3
        font.family: Theme.mono
        font.pixelSize: 12
    }

    component PresetRow: AbstractButton {
        id: row
        property int preset
        property string label
        property string desc
        readonly property bool chosen: menu.app.preset === preset

        width: parent.width
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        enabled: !menu.exporter.running
        topPadding: 9
        bottomPadding: 9
        leftPadding: 12
        rightPadding: 12
        onClicked: menu.app.preset = preset

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            radius: Theme.r2
            color: row.hovered || row.chosen ? Theme.sf3 : "transparent"
            border.color: row.chosen ? Theme.aFill : "transparent"
            border.width: row.chosen ? 1 : 0
        }
        contentItem: Column {
            spacing: 2
            Text { text: row.label; color: Theme.tx; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { text: row.desc; color: Theme.tx3; font.pixelSize: 12 }
        }
    }
}
