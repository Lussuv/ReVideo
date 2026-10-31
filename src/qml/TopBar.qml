import QtQuick

Rectangle {
    id: bar
    required property var app
    readonly property bool has: app.hasVideo
    /// Left edge of the Info tab; the info popover hangs below it.
    readonly property real infoX: row.x + infoTab.x

    color: Theme.bg2
    implicitHeight: row.implicitHeight + 16

    Row {
        id: row
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Row {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: "Re"; color: Theme.tx; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { text: "Video"; color: Theme.aFill; font.pixelSize: 17; font.weight: Font.DemiBold }
        }
        Item { width: 12; height: 1 }
        Btn {
            iconName: "folder"
            text: "Datei öffnen"
            verticalPadding: 7
            horizontalPadding: 12
            onClicked: bar.app.openFile()
        }
        Btn {
            iconName: "edit"
            text: "Bearbeiten"
            active: bar.app.trimOpen
            enabled: bar.has
            verticalPadding: 7
            horizontalPadding: 12
            onClicked: bar.app.trimOpen = !bar.app.trimOpen
        }
        Btn {
            id: infoTab
            iconName: "info"
            text: "Info"
            active: bar.app.infoOpen
            enabled: bar.has
            verticalPadding: 7
            horizontalPadding: 12
            onClicked: bar.app.infoOpen = !bar.app.infoOpen
        }
        Btn {
            iconName: "camera"
            text: "Frame speichern"
            enabled: bar.has
            verticalPadding: 7
            horizontalPadding: 12
            onClicked: bar.app.saveFrame()
        }
        Btn {
            iconName: "skipBack"
            tip: "Vorheriges Video"
            enabled: bar.has
            padding: 8
            onClicked: bar.app.navigate(-1)
        }
        Btn {
            iconName: "skipFwd"
            tip: "Nächstes Video"
            enabled: bar.has
            padding: 8
            onClicked: bar.app.navigate(1)
        }
        Btn {
            variant: "tabDanger"
            iconName: "trash"
            tip: bar.app.clipsOpen ? "Clip entfernen (Entf)" : "Video löschen (Entf)"
            enabled: bar.has
            padding: 8
            onClicked: bar.app.askDelete()
        }
    }

    Btn {
        readonly property var updater: bar.app.updater
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: updater.available
        variant: "primary"
        verticalPadding: 6
        horizontalPadding: 14
        enabled: !updater.busy
        text: updater.busy ? "Update wird geladen …" : "Update " + updater.version
        tip: !updater.canInstall ? "Download-Seite öffnen"
                                 : updater.busy ? "ReVideo startet danach neu" : "Herunterladen und installieren"
        onClicked: updater.install()
    }
}
