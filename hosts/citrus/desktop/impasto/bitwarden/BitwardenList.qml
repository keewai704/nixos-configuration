import QtQuick
import QtQuick.Layouts
import Quickshell

import "../theme"
import "../components"

ColumnLayout {
    id: root

    readonly property var rows: BitwardenService.rows

    spacing: 8

    Component.onCompleted: field.forceActiveFocus()

    function step(delta) {
        const count = root.rows.length
        if (count === 0)
            return
        let index = list.currentIndex + delta
        if (index < 0)
            index = count - 1
        if (index >= count)
            index = 0
        list.currentIndex = index
        BitwardenService.select(root.rows[index].id)
        list.positionViewAtIndex(index, ListView.Contain)
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        radius: Theme.radiusSmall
        color: Theme.island
        border.width: 1
        border.color: field.activeFocus ? Theme.accent : Theme.borderIn(QsWindow.window)

        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 8

            Text {
                text: "󰍉"
                font.family: Theme.fontMono
                font.pixelSize: 13
                color: Theme.textMuted
            }

            TextInput {
                id: field

                Layout.fillWidth: true
                text: BitwardenService.search
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                clip: true

                onTextEdited: {
                    BitwardenService.search = text
                    list.currentIndex = 0
                }
                onAccepted: root.step(0)
                Keys.onDownPressed: root.step(1)
                Keys.onUpPressed: root.step(-1)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: field.text === ""
                    text: Tr.t("Search the vault")
                    elide: Text.ElideRight
                    font: field.font
                    color: Theme.textMuted
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: chips.implicitHeight

        Flow {
            id: chips

            width: parent.width
            spacing: 4

            Repeater {
                model: BitwardenService.filterLabels

                PillButton {
                    required property string modelData
                    required property int index

                    text: modelData
                    active: index === BitwardenService.filterIndex
                    implicitHeight: 24
                    horizontalPadding: 8
                    onClicked: {
                        BitwardenService.filterIndex = index
                        list.currentIndex = 0
                    }
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Text {
            anchors.centerIn: parent
            width: parent.width - 20
            visible: root.rows.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: BitwardenService.search.trim() !== ""
                ? Tr.t("No matching items") : Tr.t("This vault is empty")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeRegular
            color: Theme.textMuted
        }

        ListView {
            id: list

            anchors.fill: parent
            clip: true
            spacing: 2
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds

            model: ScriptModel {
                values: root.rows
                objectProp: "id"

                onValuesChanged: {
                    if (list.currentIndex >= root.rows.length)
                        list.currentIndex = 0
                }
            }

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                readonly property bool chosen: BitwardenService.selectedId === row.modelData.id
                readonly property string type: BitwardenService.entryType(row.modelData,
                    BitwardenService.details[row.modelData.id] ?? null)

                width: ListView.view.width
                height: 50
                radius: Theme.radiusSmall
                color: row.chosen ? Theme.surfaceHoverIn(QsWindow.window)
                    : (rowHover.hovered ? Theme.surfaceIn(QsWindow.window) : "transparent")

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: height / 2
                        color: Theme.surfaceIn(QsWindow.window)

                        Text {
                            anchors.centerIn: parent
                            text: BitwardenService.typeGlyph(row.type)
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                            color: row.chosen ? Theme.accent : Theme.textMuted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name ?? ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeRegular
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }

                        Text {
                            Layout.fillWidth: true
                            text: BitwardenService.subtitleOf(row.modelData)
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textMuted
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        list.currentIndex = row.index
                        BitwardenService.select(row.modelData.id)
                    }
                }
            }
        }
    }
}
