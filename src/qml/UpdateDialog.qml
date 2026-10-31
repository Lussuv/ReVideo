import QtQuick

Rectangle {
    id: dlg
    required property var app

    color: Theme.scrim

    MouseArea {
        anchors.fill: parent
        onClicked: dlg.app.updatePromptDismissed = true
    }

    Sheet {
        anchors.centerIn: parent
        width: col.width + 44
        height: col.implicitHeight + 44

        MouseArea { anchors.fill: parent }

        Column {
            id: col
            x: 22
            y: 22
            width: 420
            spacing: 8

            Text { text: "Neues Update verfügbar"; color: Theme.tx; font.pixelSize: 19; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "ReVideo " + Qt.application.version + " → " + dlg.app.updater.version
                      + (dlg.app.updater.canInstall ? "\nReVideo startet nach der Installation neu."
                                                    : "\nDie Download-Seite wird im Browser geöffnet.")
                color: Theme.tx2
                font.pixelSize: 15
                wrapMode: Text.Wrap
            }
            Item { width: 1; height: 8 }
            Row {
                anchors.right: parent.right
                spacing: 10
                Btn {
                    variant: "secondary"
                    text: "Nicht jetzt"
                    verticalPadding: 8
                    horizontalPadding: 18
                    onClicked: dlg.app.updatePromptDismissed = true
                }
                Btn {
                    variant: "primary"
                    text: "Jetzt installieren"
                    verticalPadding: 8
                    horizontalPadding: 18
                    onClicked: dlg.app.installUpdate()
                }
            }
        }
    }
}
