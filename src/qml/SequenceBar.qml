import QtQuick

// The whole timeline while no clip is selected: every clip by its length with its
// thumbnail, and the playhead; click or drag to seek.
Item {
    id: overview
    required property var app

    /// Same insets as the trim timeline, so nothing jumps when switching.
    readonly property real ticksH: 20
    readonly property real inset: 10
    readonly property real trackW: width - 2 * inset

    function xOf(t) {
        return inset + (app.clipsTotal > 0 ? Math.min(Math.max(t / app.clipsTotal, 0), 1) * trackW : 0)
    }
    function timeAt(x) {
        return Math.min(Math.max((x - inset) / trackW, 0), 1) * app.clipsTotal
    }

    Text {
        x: overview.inset
        text: "Gesamte Timeline"
        color: Theme.tx3
        font.pixelSize: 11
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: overview.inset
        text: Util.formatTime(overview.app.timelinePosition, true) + " / " + Util.formatTime(overview.app.clipsTotal, true)
        color: Theme.tx3
        font.family: Theme.mono
        font.pixelSize: 11
    }

    Row {
        x: overview.inset
        y: overview.ticksH
        width: overview.trackW
        height: parent.height - overview.ticksH

        Repeater {
            model: overview.app.clips

            Rectangle {
                id: block
                required property int index
                required property string name
                required property string thumb
                required property real start
                required property real end
                readonly property bool playing: block.index === overview.app.timelineIndex

                width: overview.app.clipsTotal > 0 ? Math.max(block.end - block.start, 0) / overview.app.clipsTotal * overview.trackW : 0
                height: parent.height
                color: Theme.sf
                border.color: playing ? Theme.aText : Theme.bg
                border.width: playing ? 2 : 1
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: block.border.width
                    source: block.thumb
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.7
                }
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    text: block.name
                    elide: Text.ElideRight
                    color: Theme.tx
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.6)
                    font.pixelSize: 11
                }
            }
        }
    }

    Rectangle {
        x: overview.xOf(overview.app.timelinePosition) - 1
        y: overview.ticksH - 4
        width: 2
        height: parent.height - overview.ticksH + 8
        color: Theme.tx
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        onPressed: m => {
            overview.app.clearFocus()
            overview.app.beginDrag()
            overview.app.seekTimeline(overview.timeAt(m.x))
        }
        onPositionChanged: m => {
            if (pressed)
                overview.app.seekTimeline(overview.timeAt(m.x))
        }
        onReleased: overview.app.endDrag()
        onCanceled: overview.app.endDrag()
    }
}
