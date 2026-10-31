import QtQuick

Sheet {
    id: pop
    required property var app
    readonly property var player: app.player

    width: col.width + 32
    height: col.implicitHeight + 32

    MouseArea { anchors.fill: parent }

    Column {
        id: col
        x: 16
        y: 16
        width: 320
        spacing: 10

        Item {
            width: parent.width
            height: closeBtn.implicitHeight
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pop.app.audioOnly ? "Musikdetails" : "Videodetails"
                color: Theme.tx2
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Btn {
                id: closeBtn
                anchors.right: parent.right
                variant: "ghost"
                iconName: "close"
                iconSize: 14
                padding: 4
                onClicked: pop.app.infoOpen = false
            }
        }
        Line { icon: "file"; value: Util.fileName(pop.player.path) }
        Line {
            visible: pop.player.hasVideo
            icon: "frame"
            value: pop.player.videoWidth + " × " + pop.player.videoHeight
                   + " (" + Util.aspectRatio(pop.player.videoWidth, pop.player.videoHeight) + ")"
        }
        Line { icon: "clock"; value: Util.formatTime(pop.player.duration, false) }
        Line { icon: "drive"; value: Util.formatBytes(Util.fileSize(pop.player.path)) }
        Rectangle { width: parent.width; height: 1; color: Theme.lnSoft }
        Kv { k: "Codec"; v: pop.player.codec.toUpperCase() }
        Kv { k: "Container"; v: "." + Util.suffix(pop.player.path) }
        Kv { k: "Framerate"; v: pop.player.fps.toFixed(2) + " fps"; visible: pop.player.hasVideo }
        Kv { k: "Titel"; v: pop.player.title; visible: pop.app.audioOnly }
        Kv { k: "Interpret"; v: pop.player.artist; visible: pop.app.audioOnly && v !== "" }
        Kv { k: "Audio"; v: pop.player.hasAudio ? "Ja" : "Nein" }
    }

    component Line: Row {
        property string icon
        property string value
        width: parent.width
        spacing: 10
        Icon { name: parent.icon; size: 16; color: Theme.tx3 }
        Text {
            width: parent.width - 26
            text: parent.value
            color: Theme.tx
            font.pixelSize: 14
            wrapMode: Text.WrapAnywhere
        }
    }

    component Kv: Item {
        property string k
        property string v
        width: parent.width
        implicitHeight: key.implicitHeight
        Text { id: key; text: parent.k; color: Theme.tx3; font.pixelSize: 13 }
        Text {
            anchors.right: parent.right
            text: parent.v
            color: Theme.tx
            font.family: Theme.mono
            font.pixelSize: 13
        }
    }
}
