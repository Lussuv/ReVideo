import QtQuick
import QtQuick.Controls.Basic

ToolTip {
    id: t
    property bool below: true

    delay: 400
    margins: 4
    x: (parent.width - width) / 2
    y: below ? parent.height + 6 : -height - 6
    topPadding: 4
    bottomPadding: 4
    leftPadding: 8
    rightPadding: 8

    contentItem: Text {
        text: t.text
        color: Theme.tx
        font.pixelSize: 13
    }
    background: Rectangle {
        color: Theme.sf4
        radius: Theme.r1
    }
}
