import QtQuick
import QtQuick.Layouts
import Quickshell

import "../theme"

ColumnLayout {
    id: root

    property string title: ""
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: 6

    Text {
        Layout.fillWidth: true
        text: root.title
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Theme.textMuted
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: body.implicitHeight + 24
        radius: Theme.radiusMedium
        color: Theme.surfaceIn(QsWindow.window)
        border.width: 1
        border.color: Theme.borderIn(QsWindow.window)

        ColumnLayout {
            id: body

            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
        }
    }
}
