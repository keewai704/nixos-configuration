pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell

Item {
    id: pages
    required property var shell
    required property string page
    required property color accent
    readonly property var desktop: shell.desktop
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
        color: "#efedf4"
        font.family: "Inter"
        font.pixelSize: 13
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Action: Button {
        id: action
        implicitHeight: 32
        Accessible.name: text
        contentItem: Caption {
            text: action.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            color: action.hovered || action.visualFocus ? "#30272e" : "#17151c"
            border.color: action.visualFocus ? pages.accent : "transparent"
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
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Caption {
                text: pages.page === "wallpaper" ? "Wallpaper" : pages.page === "clipboard" ? "Clipboard" : "Open windows"
                font.pixelSize: 22
                font.bold: true
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
            color: "#8e8996"
            font.pixelSize: 11
        }
        Caption {
            Layout.fillWidth: true
            visible: !!pages.desktop.error
            text: pages.desktop.error
            color: pages.accent
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
        TextField {
            id: filter
            Layout.fillWidth: true
            visible: pages.page === "clipboard" || pages.page === "windows"
            placeholderText: pages.page === "clipboard" ? "Search clipboard…" : "Search windows…"
            color: "#efedf4"
            placeholderTextColor: "#8e8996"
            font.family: "Inter"
            background: Rectangle {
                color: "#17151c"
                radius: 9
                border.color: filter.activeFocus ? pages.accent : "transparent"
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
            delegate: ItemDelegate {
                id: wallpaper
                required property var modelData
                width: GridView.view.cellWidth - 8
                height: 117
                Accessible.name: modelData.name
                background: Rectangle {
                    color: "#17151c"
                    radius: 10
                    border.width: 2
                    border.color: wallpaper.modelData.path === pages.desktop.wallpaper || wallpaper.visualFocus ? pages.accent : "transparent"
                }
                contentItem: ColumnLayout {
                    Image {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        source: "file://" + wallpaper.modelData.path.split("/").map(encodeURIComponent).join("/")
                        sourceSize.width: 360
                        sourceSize.height: 180
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Caption {
                        text: wallpaper.modelData.name
                        Layout.fillWidth: true
                        font.pixelSize: 11
                    }
                }
                onClicked: pages.desktop.run(["wallpaper-set", modelData.path])
            }
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pages.page !== "wallpaper"
            clip: true
            spacing: 6
            model: (pages.page === "clipboard" ? pages.desktop.clipboard : pages.page === "windows" ? pages.desktop.windows : []).filter(item => ((item.text || item.title || "") + " " + (item.app || "")).toLowerCase().includes(filter.text.toLowerCase()))
            delegate: ItemDelegate {
                id: entry
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 58
                readonly property bool clipboardItem: modelData.id !== undefined
                Accessible.name: modelData.text || modelData.title || ""
                background: Rectangle {
                    radius: 10
                    color: entry.hovered || entry.visualFocus || (filter.activeFocus && entry.index === list.currentIndex) ? "#30272e" : "#17151c"
                }
                contentItem: RowLayout {
                    ColumnLayout {
                        Layout.fillWidth: true
                        Caption {
                            Layout.fillWidth: true
                            text: entry.modelData.text || entry.modelData.title || ""
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Caption {
                            Layout.fillWidth: true
                            visible: !entry.clipboardItem
                            text: (entry.modelData.app || "") + " · Workspace " + (entry.modelData.workspace || "")
                            color: "#8e8996"
                            font.pixelSize: 10
                        }
                    }
                    Action {
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
                color: "#8e8996"
            }
        }
    }
}
