import QtQuick

Rectangle {
    id: dlg
    required property var app

    color: Theme.scrim

    MouseArea {
        anchors.fill: parent
        onClicked: dlg.app.deleteChoice = -1
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

            Text { text: "Datei löschen?"; color: Theme.tx; font.pixelSize: 19; font.weight: Font.DemiBold }
            Text {
                width: parent.width
                text: "„" + Util.fileName(dlg.app.player.path) + "“ in den Papierkorb verschieben?"
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
                    text: "Abbrechen"
                    active: dlg.app.deleteChoice === 0
                    verticalPadding: 8
                    horizontalPadding: 18
                    onClicked: dlg.app.deleteChoice = -1
                }
                Btn {
                    variant: "danger"
                    text: "Löschen"
                    active: dlg.app.deleteChoice === 1
                    verticalPadding: 8
                    horizontalPadding: 18
                    onClicked: dlg.app.confirmDelete()
                }
            }
        }
    }
}
