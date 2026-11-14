import QtQuick
import QtQuick.Layouts
import Quickshell

import "../theme"
import "../components"

ColumnLayout {
    id: root

    property string label: ""
    property string value: ""
    property string maskedText: BitwardenService.mask()
    property bool secretValue: false
    property string revealKey: ""
    property string copyMode: ""
    property string copyLabel: root.label
    property string trailing: ""
    property string openUri: ""
    property bool flag: false
    property bool checked: false
    property int maxLines: 2
    property bool mono: false

    Layout.fillWidth: true
    spacing: 3

    readonly property bool opened: root.secretValue && root.revealKey !== ""
        && BitwardenService.revealed[root.revealKey] === true
    readonly property string shown: root.secretValue && !root.opened ? root.maskedText : root.value

    Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        visible: !root.flag
        text: root.label
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLabel
        color: Theme.textMuted
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.flag
        spacing: 7

        Text {
            text: root.checked ? "󰄬" : "󰄱"
            font.family: Theme.fontMono
            font.pixelSize: 13
            color: root.checked ? Theme.accent : Theme.textMuted
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeRegular
            color: Theme.text
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !root.flag
        spacing: 2

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.shown
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: root.secretValue && !root.opened ? 1 : root.maxLines
            elide: Text.ElideRight
            font.family: root.mono ? Theme.fontMono : Theme.fontFamily
            font.pixelSize: Theme.fontSizeRegular
            color: Theme.text
        }

        Text {
            Layout.alignment: Qt.AlignTop
            visible: text !== ""
            text: root.trailing
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }

        IconButton {
            visible: root.openUri !== ""
            implicitWidth: 26
            implicitHeight: 22
            iconSize: 12
            icon: "󰏌"
            onClicked: BitwardenService.openUri(root.openUri)
        }

        IconButton {
            visible: root.secretValue && root.revealKey !== ""
            implicitWidth: 26
            implicitHeight: 22
            iconSize: 12
            icon: root.opened ? "󰈈" : "󰈉"
            onClicked: BitwardenService.toggleReveal(root.revealKey)
        }

        IconButton {
            visible: root.copyMode !== ""
            implicitWidth: 26
            implicitHeight: 22
            iconSize: 12
            icon: "󰆏"
            onClicked: BitwardenService.copy(root.copyMode, root.copyLabel)
        }
    }
}
