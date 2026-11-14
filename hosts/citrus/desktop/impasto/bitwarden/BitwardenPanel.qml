import QtQuick
import QtQuick.Layouts
import Quickshell

import "../theme"
import "../components"

ColumnLayout {
    id: root

    signal closed()

    readonly property string view: BitwardenService.view
    readonly property bool ready: root.view === "ready"
    readonly property bool form: BitwardenService.editingAccount || root.view === "setup"

    readonly property string status: {
        if (BitwardenService.copyNotice !== "")
            return BitwardenService.copyNotice
        if (BitwardenService.notice !== "")
            return BitwardenService.notice
        if (root.ready)
            return BitwardenService.rows.length === 1
                ? Tr.t("1 item") : Tr.t("%1 items").arg(BitwardenService.rows.length)
        return ""
    }

    readonly property string headline: {
        if (root.form)
            return BitwardenService.accountEmail === ""
                ? Tr.t("Set up your account") : Tr.t("Account")
        if (root.view === "no_rbw")
            return Tr.t("rbw is not installed")
        if (root.view === "locked")
            return Tr.t("Vault locked")
        if (root.view === "unlocking")
            return Tr.t("Waiting for the master password")
        if (root.view === "syncing")
            return Tr.t("Reading the vault")
        if (root.view === "error")
            return Tr.t("Could not read the vault")
        return Tr.t("Checking the vault")
    }

    readonly property string body: {
        if (root.form)
            return BitwardenService.accountEmail === ""
                ? Tr.t("Add your Bitwarden account email. Optionally set a self-hosted server URL.") : ""
        if (root.view === "no_rbw")
            return Tr.t("This panel reads the vault through rbw. Install it and reopen the panel.")
        if (root.view === "locked")
            return BitwardenService.problem !== "" ? BitwardenService.problem
                : Tr.t("Unlock the vault to read your items. rbw asks for the master password in its pinentry window.")
        if (root.view === "unlocking")
            return Tr.t("Enter the master password in the pinentry window. The vault opens as soon as rbw reports success.")
        if (root.view === "error")
            return BitwardenService.problem
        return ""
    }

    spacing: 10

    Component.onCompleted: BitwardenService.begin()
    Component.onDestruction: BitwardenService.dismiss()

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            implicitWidth: 30
            implicitHeight: 30
            radius: width / 2
            color: Theme.surfaceIn(QsWindow.window)

            Text {
                anchors.centerIn: parent
                text: root.ready ? "󰦝" : "󰌾"
                font.family: Theme.fontMono
                font.pixelSize: 15
                color: Theme.accent
            }
        }

        Text {
            text: Tr.t("Bitwarden")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.DemiBold
            color: Theme.text
        }

        Text {
            Layout.fillWidth: true
            text: root.status
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textMuted
        }

        IconButton {
            visible: root.ready && !root.form
            icon: "󰑐"
            onClicked: BitwardenService.sync()
        }

        IconButton {
            visible: root.ready && !root.form
            icon: "󰌾"
            onClicked: BitwardenService.lock()
        }

        IconButton {
            visible: !root.form
            icon: "󰒓"
            onClicked: BitwardenService.editAccount()
        }

        IconButton {
            icon: "󰅖"
            onClicked: root.closed()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.borderIn(QsWindow.window)
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        RowLayout {
            anchors.fill: parent
            visible: root.ready && !root.form
            spacing: 12

            Item {
                Layout.preferredWidth: 320
                Layout.minimumWidth: 320
                Layout.maximumWidth: 320
                Layout.fillHeight: true

                BitwardenList {
                    anchors.fill: parent
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Theme.borderIn(QsWindow.window)
            }

            BitwardenDetail {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            visible: !root.ready || root.form
            spacing: 12

            Item { Layout.fillHeight: true }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.form ? "󰒓"
                    : (root.view === "locked" ? "󰌾"
                    : (root.view === "unlocking" ? "󰥔"
                    : (root.view === "syncing" ? "󰑐"
                    : (root.view === "error" || root.view === "no_rbw" ? "󰅚" : "󰌾"))))
                font.family: Theme.fontMono
                font.pixelSize: 34
                color: root.view === "error" || root.view === "no_rbw"
                    ? Theme.indicatorWarn : Theme.textMuted
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 520
                text: root.headline
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.text
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 520
                visible: text !== ""
                text: root.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeRegular
                color: Theme.textMuted
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 460
                Layout.topMargin: 4
                visible: root.form
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: Tr.t("Account email")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLabel
                        color: Theme.textMuted
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: Theme.radiusSmall
                        color: Theme.island
                        border.width: 1
                        border.color: emailField.activeFocus ? Theme.accent : Theme.borderIn(QsWindow.window)

                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        TextInput {
                            id: emailField

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            text: BitwardenService.draftEmail
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.text
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentText
                            clip: true

                            onTextEdited: BitwardenService.draftEmail = text
                            onAccepted: BitwardenService.saveAccount()

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                visible: emailField.text === ""
                                text: Tr.t("name@example.com")
                                elide: Text.ElideRight
                                font: emailField.font
                                color: Theme.textMuted
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 460
                visible: root.form
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: Tr.t("Server URL")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLabel
                        color: Theme.textMuted
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: Theme.radiusSmall
                        color: Theme.island
                        border.width: 1
                        border.color: serverField.activeFocus ? Theme.accent : Theme.borderIn(QsWindow.window)

                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        TextInput {
                            id: serverField

                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            text: BitwardenService.draftBaseUrl
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.text
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentText
                            clip: true

                            onTextEdited: BitwardenService.draftBaseUrl = text
                            onAccepted: BitwardenService.saveAccount()

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                visible: serverField.text === ""
                                text: Tr.t("https://vault.bitwarden.com")
                                elide: Text.ElideRight
                                font: serverField.font
                                color: Theme.textMuted
                            }
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 520
                visible: BitwardenService.setupError !== ""
                text: BitwardenService.setupError
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.indicatorBad
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: 8

                PillButton {
                    visible: root.form
                    text: Tr.t("Save")
                    active: true
                    onClicked: BitwardenService.saveAccount()
                }

                PillButton {
                    visible: root.form
                    text: Tr.t("Recheck")
                    onClicked: BitwardenService.check()
                }

                PillButton {
                    visible: root.form && root.ready
                    text: Tr.t("Cancel")
                    onClicked: BitwardenService.cancelAccount()
                }

                PillButton {
                    visible: !root.form && root.view === "locked"
                    text: Tr.t("Unlock")
                    icon: "󰋠"
                    active: true
                    onClicked: BitwardenService.unlock()
                }

                PillButton {
                    visible: !root.form && (root.view === "error" || root.view === "no_rbw")
                    text: Tr.t("Retry")
                    icon: "󰑐"
                    active: root.view === "error"
                    onClicked: BitwardenService.check()
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
