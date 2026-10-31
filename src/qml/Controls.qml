import QtQuick

Sheet {
    id: c
    required property var app
    readonly property var player: app.player
    // While trimming the bar spans only the trim range, stretched to full width; on the
    // whole timeline it spans all clips.
    readonly property bool timeline: app.sequenceMode
    readonly property real from: timeline ? 0 : app.trimOpen ? app.trimStart : 0
    readonly property real to: Math.max(timeline ? app.clipsTotal : app.trimOpen ? app.trimEnd : app.duration, from + 0.01)
    readonly property real at: timeline ? app.timelinePosition : app.position

    elevation: 2
    color: Qt.alpha(Theme.bg2, 0.92)
    border.color: Theme.lnSoft
    implicitHeight: col.implicitHeight + 20

    HoverHandler {
        onHoveredChanged: {
            c.app.controlsHovered = hovered
            c.app.showControls()
        }
    }
    // Clicks on the bar's background must not reach the video (play/pause).
    MouseArea { anchors.fill: parent }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        SeekSlider {
            width: parent.width
            from: c.from
            to: c.to
            value: Math.min(Math.max(c.at, c.from), c.to)
            onMoved: {
                c.app.beginDrag()
                if (c.timeline)
                    c.app.seekTimeline(value)
                else
                    c.app.seekTo(value)
            }
            onPressedChanged: if (!pressed) c.app.endDrag()
        }

        Item {
            width: parent.width
            height: center.implicitHeight

            Row {
                id: center
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Ctrl { iconName: "frameBack"; tip: "Vorheriger Frame (,)"; onClicked: c.app.stepFrame(-1) }
                Ctrl { iconName: "skipBack"; tip: "5 s zurück (←)"; onClicked: c.app.skip(-5) }
                Btn {
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "primary"
                    iconName: c.player.paused || c.player.eof ? "play" : "pause"
                    iconSize: 20
                    padding: 10
                    onClicked: c.app.togglePlay()
                }
                Ctrl { iconName: "skipFwd"; tip: "5 s vor (→)"; onClicked: c.app.skip(5) }
                Ctrl { iconName: "frameFwd"; tip: "Nächster Frame (.)"; onClicked: c.app.stepFrame(1) }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: Util.formatTime(c.at, c.app.trimOpen)
                        color: Theme.tx
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }
                    Text { text: " / "; color: Theme.tx3; font.family: Theme.mono; font.pixelSize: 13 }
                    Text {
                        text: Util.formatTime(c.to, c.app.trimOpen)
                        color: Theme.tx3
                        font.family: Theme.mono
                        font.pixelSize: 13
                    }
                }
                Item { width: 8; height: 1 }
                Ctrl {
                    iconName: c.player.muted || c.player.volume === 0 ? "mute" : "volume"
                    tip: "Ton an/aus"
                    onClicked: c.app.toggleMute()
                }
                SeekSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    from: 0
                    to: 1
                    value: c.player.muted ? 0 : c.player.volume
                    onMoved: c.app.setVolume(value)
                    onPressedChanged: if (!pressed) c.app.saveSettings()
                }
                Ctrl { iconName: "fullscreen"; tip: "Vollbild (F11)"; onClicked: c.app.toggleFullscreen() }
            }
        }
    }

    component Ctrl: Btn {
        anchors.verticalCenter: parent.verticalCenter
        variant: "ghost"
        iconSize: 18
        iconColor: Theme.tx
        padding: 8
        tipBelow: false
    }
}
