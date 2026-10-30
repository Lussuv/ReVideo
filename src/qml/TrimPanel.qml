import QtQuick
import QtQuick.Controls.Basic

Sheet {
    id: panel
    required property var app

    elevation: 2
    color: Theme.bg2
    radius: Theme.r4
    border.color: Theme.lnSoft

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        height: exportBtn.implicitHeight

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Trim"
                color: Theme.tx
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Item { width: 6; height: 1 }
            TimeField {
                value: panel.app.trimStart
                onCommitted: v => {
                    panel.app.setTrim(v, panel.app.trimEnd)
                    panel.app.seekTo(panel.app.trimStart)
                }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "→"; color: Theme.tx3; font.pixelSize: 16 }
            TimeField {
                value: panel.app.trimEnd
                onCommitted: v => {
                    panel.app.setTrim(panel.app.trimStart, v)
                    panel.app.seekTo(panel.app.trimEnd - panel.app.frame)
                }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "•"; color: Theme.tx3; font.pixelSize: 15 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Util.formatTime(panel.app.trimEnd - panel.app.trimStart, true)
                color: Theme.tx
                font.family: Theme.mono
                font.pixelSize: 13
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Länge"; color: Theme.tx3; font.pixelSize: 13 }
        }

        Btn {
            id: exportBtn
            anchors.right: parent.right
            variant: "secondary"
            iconName: "upload"
            text: panel.app.exporter.running ? "Exportiere … " + panel.app.exporter.percent.toFixed(0) + " %" : "Export"
            verticalPadding: 7
            horizontalPadding: 14
            onClicked: panel.app.exportMenuOpen = !panel.app.exportMenuOpen
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        height: 84

        // Same insets as the timeline's track.
        Rectangle {
            x: timeline.handleW
            y: timeline.ticksH
            width: parent.width - 2 * timeline.handleW
            height: parent.height - timeline.ticksH
            color: Theme.sf
            radius: Theme.r1
            clip: true

            Row {
                anchors.fill: parent
                Repeater {
                    model: panel.app.thumbCount
                    Image {
                        required property int index
                        width: parent.width / panel.app.thumbCount
                        height: parent.height
                        source: panel.app.thumbnails[index] ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }
        }

        Timeline {
            id: timeline
            anchors.fill: parent
            app: panel.app
        }
    }

    component TimeField: TextField {
        id: field
        property real value
        signal committed(real v)

        anchors.verticalCenter: parent.verticalCenter
        width: 120
        topPadding: 5
        bottomPadding: 5
        leftPadding: 10
        rightPadding: 10
        font.family: Theme.mono
        font.pixelSize: 13
        color: Theme.tx
        selectionColor: Theme.aRing
        selectedTextColor: Theme.tx
        text: Util.formatTime(value, true)
        background: Rectangle {
            color: Theme.sf
            radius: Theme.r1
            border.color: field.activeFocus ? Theme.aRing : Theme.ln
            border.width: field.activeFocus ? 2 : 1
        }
        // Typing replaces the binding; restore it once editing ends.
        onActiveFocusChanged: if (!activeFocus) text = Qt.binding(() => Util.formatTime(value, true))
        onAccepted: {
            const v = Util.parseTime(text)
            panel.app.clearFocus()
            if (v >= 0)
                committed(v)
        }
    }
}
