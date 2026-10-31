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
            visible: !panel.app.sequenceMode
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

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.app.sequenceMode
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Timeline"
                color: Theme.tx
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Item { width: 6; height: 1 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Util.formatTime(panel.app.clipsTotal, true)
                color: Theme.tx
                font.family: Theme.mono
                font.pixelSize: 13
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Länge"; color: Theme.tx3; font.pixelSize: 13 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "· Clip anklicken zum Bearbeiten"
                color: Theme.tx3
                font.pixelSize: 13
            }
        }

        Row {
            anchors.right: parent.right
            spacing: 8

            Btn {
                visible: !panel.app.audioOnly
                variant: "secondary"
                iconName: "plus"
                text: "Clip hinzufügen"
                verticalPadding: 7
                horizontalPadding: 14
                onClicked: panel.app.clipsOpen ? panel.app.pickClips(panel.app.clips.count) : panel.app.openClips()
            }
            Btn {
                id: exportBtn
                variant: "secondary"
                iconName: "upload"
                text: panel.app.exporter.running ? "Exportiere … " + panel.app.exporter.percent.toFixed(0) + " %" : "Export"
                verticalPadding: 7
                horizontalPadding: 14
                onClicked: panel.app.exportMenuOpen = !panel.app.exportMenuOpen
            }
        }
    }

    Item {
        id: timelineBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 12
        height: 84

        // Same insets as the timeline's track.
        Rectangle {
            visible: !panel.app.sequenceMode
            x: timeline.handleW
            y: timeline.ticksH
            width: parent.width - 2 * timeline.handleW
            height: parent.height - timeline.ticksH
            color: Theme.sf
            radius: Theme.r1
            clip: true

            Row {
                anchors.fill: parent
                visible: !panel.app.audioOnly
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

            // A song: its waveform over the whole length, mirrored around the middle.
            Canvas {
                id: wave
                readonly property var paintKey: [width, height, panel.app.trackPeaks]
                anchors.fill: parent
                visible: panel.app.audioOnly
                onPaintKeyChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const peaks = panel.app.trackPeaks
                    if (!peaks || peaks.length === 0)
                        return
                    ctx.fillStyle = Theme.aText
                    ctx.globalAlpha = 0.7
                    const mid = height / 2, amp = height / 2 - 6
                    // 2 px bars with 1 px gaps; each takes the loudest bucket under it.
                    for (let px = 0; px < width; px += 3) {
                        const from = Math.floor(px / width * peaks.length)
                        const to = Math.max(Math.floor((px + 3) / width * peaks.length), from + 1)
                        let peak = 0
                        for (let i = from; i < Math.min(to, peaks.length); i++)
                            peak = Math.max(peak, peaks[i])
                        const h = Math.max(peak * amp, 0.5)
                        ctx.fillRect(px, mid - h, 2, 2 * h)
                    }
                }
            }
        }

        Timeline {
            id: timeline
            visible: !panel.app.sequenceMode
            anchors.fill: parent
            app: panel.app
        }
        SequenceBar {
            visible: panel.app.sequenceMode
            anchors.fill: parent
            app: panel.app
        }
    }

    readonly property real clipAreaHeight: clipArea.height

    // Clips and music sit on their own sunken surface, apart from the trim above.
    Rectangle {
        id: clipArea
        visible: panel.app.clipsOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: timelineBox.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 14
        height: strip.implicitHeight + 20
        radius: Theme.r2
        color: Theme.bg
        border.color: Theme.lnSoft

        ClipStrip {
            id: strip
            app: panel.app
            anchors.fill: parent
            anchors.margins: 10
        }

        // Closes the whole area, on its corner.
        Btn {
            x: parent.width - width / 2 - 4
            y: -height / 2 + 4
            variant: "danger"
            iconName: "close"
            iconSize: 12
            padding: 4
            tip: "Clip-Leiste schließen"
            onClicked: panel.app.closeClips()
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
