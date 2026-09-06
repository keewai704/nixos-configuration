pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Widgets

Item {
    id: pages
    required property var shell
    required property string page
    readonly property var theme: shell.theme
    readonly property var desktop: shell.desktop
    readonly property bool dialogOpen: picker.visible
    signal done
    onPageChanged: {
        filter.text = "";
        list.currentIndex = 0;
        if (page === "clipboard" || page === "windows")
            Qt.callLater(() => filter.forceActiveFocus());
    }
    function activate(item) {
        if (!item)
            return;
        desktop.run(item.id !== undefined ? ["clipboard-copy", item.id] : ["window-focus", item.address]);
        done();
    }

    component Caption: Text {
        color: pages.theme.text
        font.family: pages.theme.fontFamily
        font.pixelSize: pages.theme.fontSize
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Action: Button {
        id: action
        implicitWidth: Math.max(36, contentItem.implicitWidth + leftPadding + rightPadding)
        implicitHeight: 36
        horizontalPadding: 12
        verticalPadding: 8
        hoverEnabled: true
        Accessible.name: text
        contentItem: Caption {
            text: action.text
            color: action.down ? pages.theme.onAccent : action.enabled ? pages.theme.text : pages.theme.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            color: action.down ? pages.theme.accent : action.hovered || action.visualFocus ? pages.theme.hover : pages.theme.surface
            border.width: action.visualFocus ? 1 : 0
            border.color: pages.theme.border
        }
    }
    FileDialog {
        id: picker
        title: "Choose wallpaper"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp)"]
        currentFolder: "file://" + Quickshell.env("HOME") + "/Pictures"
        onAccepted: pages.desktop.run(["wallpaper-set", decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))])
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Caption {
                text: pages.page === "wallpaper" ? "Wallpaper" : pages.page === "clipboard" ? "Clipboard" : "Open windows"
                font.pixelSize: pages.theme.fontSize + 9
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            Action {
                text: "Refresh"
                enabled: !pages.desktop.busy
                onClicked: pages.desktop.refresh(pages.page)
            }
            Action {
                visible: pages.page === "wallpaper"
                text: "Choose file…"
                onClicked: picker.open()
            }
            Action {
                id: clear
                property bool confirm: false
                visible: pages.page === "clipboard"
                text: confirm ? "Clear all?" : "Clear"
                onVisibleChanged: confirm = false
                onClicked: {
                    if (confirm) {
                        pages.desktop.run(["clipboard-clear"]);
                        confirm = false;
                    } else
                        confirm = true;
                }
            }
        }
        Caption {
            Layout.fillWidth: true
            visible: pages.page === "wallpaper"
            text: "Add images to ~/Pictures/Wallpapers, or choose any local image."
            color: pages.theme.muted
            font.pixelSize: Math.max(11, pages.theme.fontSize - 2)
        }
        Caption {
            Layout.fillWidth: true
            visible: !!pages.desktop.error
            text: pages.desktop.error
            color: pages.theme.accent
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
        TextField {
            id: filter
            Layout.fillWidth: true
            visible: pages.page === "clipboard" || pages.page === "windows"
            placeholderText: pages.page === "clipboard" ? "Search clipboard…" : "Search windows…"
            color: pages.theme.text
            placeholderTextColor: pages.theme.muted
            font.family: pages.theme.fontFamily
            font.pixelSize: pages.theme.fontSize
            implicitHeight: 40
            leftPadding: 12
            rightPadding: 12
            topPadding: 8
            bottomPadding: 8
            background: Rectangle {
                color: pages.theme.background
                radius: 9
                border.width: filter.activeFocus ? 1 : 0
                border.color: pages.theme.accent
            }
            onTextChanged: list.currentIndex = 0
            Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
            Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
            onAccepted: pages.activate(list.model[list.currentIndex])
        }
        GridView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pages.page === "wallpaper"
            clip: true
            cellWidth: width / 3
            cellHeight: 125
            model: pages.desktop.wallpapers
            delegate: Item {
                id: gridCell
                required property var modelData
                required property int index
                width: GridView.view.cellWidth
                height: 125
                ItemDelegate {
                    id: wallpaper
                    x: (gridCell.index % 3) * (8 / 3)
                    width: gridCell.width - 16 / 3
                    height: 117
                    leftPadding: 6
                    rightPadding: 6
                    topPadding: 6
                    bottomPadding: 6
                    Accessible.name: gridCell.modelData.name
                    background: Rectangle {
                        color: pages.theme.surface
                        radius: 10
                        border.width: gridCell.modelData.path === pages.desktop.wallpaper || wallpaper.visualFocus ? 1 : 0
                        border.color: gridCell.modelData.path === pages.desktop.wallpaper ? pages.theme.accent : pages.theme.border
                    }
                    contentItem: ColumnLayout {
                        spacing: 5
                        ClippingRectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(56, Math.min(82, width * 0.48))
                            radius: 8
                            color: pages.theme.background
                            Image {
                                anchors.fill: parent
                                source: "file://" + gridCell.modelData.path.split("/").map(encodeURIComponent).join("/")
                                sourceSize.width: width * 2
                                sourceSize.height: height * 2
                                fillMode: Image.PreserveAspectFit
                                horizontalAlignment: Image.AlignHCenter
                                verticalAlignment: Image.AlignVCenter
                                asynchronous: true
                            }
                        }
                        Caption {
                            text: gridCell.modelData.name
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font.pixelSize: Math.max(11, pages.theme.fontSize - 2)
                            maximumLineCount: 1
                        }
                    }
                    onClicked: pages.desktop.run(["wallpaper-set", gridCell.modelData.path])
                }
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pages.page !== "wallpaper"
            clip: true
            spacing: 8
            model: (pages.page === "clipboard" ? pages.desktop.clipboard : pages.page === "windows" ? pages.desktop.windows : []).filter(item => ((item.text || item.title || "") + " " + (item.app || "")).toLowerCase().includes(filter.text.toLowerCase()))
            delegate: ItemDelegate {
                id: entry
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 64
                leftPadding: 10
                rightPadding: 10
                topPadding: 8
                bottomPadding: 8
                readonly property bool clipboardItem: modelData.id !== undefined
                Accessible.name: modelData.text || modelData.title || ""
                background: Rectangle {
                    radius: 10
                    color: entry.hovered || entry.visualFocus || (filter.activeFocus && entry.index === list.currentIndex) ? pages.theme.hover : pages.theme.surface
                    border.width: entry.visualFocus ? 1 : 0
                    border.color: pages.theme.border
                }
                contentItem: RowLayout {
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Caption {
                            Layout.fillWidth: true
                            text: entry.modelData.text || entry.modelData.title || ""
                            maximumLineCount: 1
                        }
                        Caption {
                            Layout.fillWidth: true
                            visible: !entry.clipboardItem
                            text: (entry.modelData.app || "") + " · Workspace " + (entry.modelData.workspace || "")
                            color: pages.theme.muted
                            font.pixelSize: Math.max(10, pages.theme.fontSize - 3)
                            maximumLineCount: 1
                        }
                    }
                    Action {
                        Layout.alignment: Qt.AlignVCenter
                        visible: entry.clipboardItem
                        text: "Delete"
                        onClicked: pages.desktop.run(["clipboard-delete", entry.modelData.id])
                    }
                }
                onClicked: pages.activate(modelData)
            }
            Caption {
                anchors.centerIn: parent
                visible: list.count === 0
                text: pages.desktop.busy ? "Loading…" : pages.page === "clipboard" ? "Clipboard is empty" : "No open windows"
                color: pages.theme.muted
            }
        }
    }
}
