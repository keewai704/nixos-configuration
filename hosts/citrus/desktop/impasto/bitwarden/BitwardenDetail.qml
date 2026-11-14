import QtQuick
import QtQuick.Layouts
import Quickshell

import "../theme"

Item {
    id: root

    readonly property var item: BitwardenService.selectedItem
    readonly property var detail: BitwardenService.selectedDetail
    readonly property var entryData: BitwardenService.selectedData
    readonly property string type: BitwardenService.selectedType
    readonly property bool loaded: root.detail !== null

    readonly property bool hasUsername: !!root.entryData && BitwardenService.isSet(root.entryData.username)
    readonly property bool hasPassword: !!root.entryData && BitwardenService.isSet(root.entryData.password)
    readonly property bool hasTotp: BitwardenService.selectedHasTotp
    readonly property bool hasCardholder: !!root.entryData && BitwardenService.isSet(root.entryData.cardholder_name)
    readonly property bool hasCardNumber: !!root.entryData && BitwardenService.isSet(root.entryData.number)
    readonly property bool hasCardExpiry: BitwardenService.cardExpiry !== ""
    readonly property bool hasCardCode: !!root.entryData && BitwardenService.isSet(root.entryData.code)
    readonly property bool hasIdentityUsername: !!root.entryData && BitwardenService.isSet(root.entryData.username)
    readonly property bool hasSsn: !!root.entryData && BitwardenService.isSet(root.entryData.ssn)
    readonly property bool hasPassport: !!root.entryData && BitwardenService.isSet(root.entryData.passport_number)
    readonly property bool hasLicense: !!root.entryData && BitwardenService.isSet(root.entryData.license_number)
    readonly property bool hasEmail: !!root.entryData && BitwardenService.isSet(root.entryData.email)
    readonly property bool hasPhone: !!root.entryData && BitwardenService.isSet(root.entryData.phone)
    readonly property bool hasAddress: BitwardenService.identityAddress !== ""
    readonly property bool hasSshPrivate: !!root.entryData && BitwardenService.isSet(root.entryData.private_key)
    readonly property bool hasSshPublic: !!root.entryData && BitwardenService.isSet(root.entryData.public_key)
    readonly property bool hasSshFingerprint: !!root.entryData && BitwardenService.isSet(root.entryData.fingerprint)

    component Chip: Rectangle {
        id: chip

        property string glyph: ""
        property string text: ""

        implicitWidth: chipRow.implicitWidth + 18
        implicitHeight: 22
        radius: height / 2
        color: Theme.surfaceIn(QsWindow.window)
        border.width: 1
        border.color: Theme.borderIn(QsWindow.window)

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.glyph !== ""
                text: chip.glyph
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLabel
                color: Theme.textMuted
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 60
        visible: root.item === null
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Tr.t("Pick an item from the list on the left to see its details.")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeRegular
        color: Theme.textMuted
    }

    Flickable {
        anchors.fill: parent
        visible: root.item !== null
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body

            width: parent.width
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    radius: Theme.radiusMedium
                    color: Theme.surfaceIn(QsWindow.window)

                    Text {
                        anchors.centerIn: parent
                        text: BitwardenService.typeGlyph(root.type)
                        font.family: Theme.fontMono
                        font.pixelSize: 20
                        color: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.item ? (root.item.name ?? "") : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.text
                    }

                    RowLayout {
                        spacing: 6

                        Chip {
                            glyph: BitwardenService.typeGlyph(root.type)
                            text: BitwardenService.typeLabel(root.type)
                        }

                        Chip {
                            glyph: "󰉋"
                            text: BitwardenService.itemFolder !== ""
                                ? BitwardenService.itemFolder : Tr.t("No folder")
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: !root.loaded
                text: Tr.t("Loading the item")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeRegular
                color: Theme.textMuted
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.loaded && BitwardenService.detailError !== ""
                wrapMode: Text.WordWrap
                text: BitwardenService.detailError
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeRegular
                color: Theme.indicatorBad
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Login" && (root.hasUsername || root.hasPassword || root.hasTotp)
                title: Tr.t("Login credentials")

                BitwardenField {
                    visible: root.hasUsername
                    label: Tr.t("Username")
                    value: root.entryData ? (root.entryData.username ?? "") : ""
                    copyMode: "username"
                }

                BitwardenField {
                    visible: root.hasPassword
                    label: Tr.t("Password")
                    value: root.entryData ? (root.entryData.password ?? "") : ""
                    secretValue: true
                    revealKey: "login:password"
                    copyMode: "password"
                }

                BitwardenField {
                    visible: root.hasTotp
                    label: Tr.t("Verification code (TOTP)")
                    value: BitwardenService.totpDisplay
                    trailing: BitwardenService.totpLeft > 0
                        ? Tr.t("%1 s").arg(BitwardenService.totpLeft) : ""
                    copyMode: "totp"
                    copyLabel: Tr.t("Verification code (TOTP)")
                    mono: true
                    maxLines: 1
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Login" && BitwardenService.uris.length > 0
                title: Tr.t("Autofill options")

                Repeater {
                    model: BitwardenService.uris

                    BitwardenField {
                        id: uriField

                        required property var modelData
                        required property int index

                        label: index === 0 ? Tr.t("Website")
                            : Tr.t("Website %1").arg(index + 1)
                        value: modelData.uri
                        copyMode: modelData.mode
                        copyLabel: uriField.label
                        openUri: modelData.uri.match(/^https?:\/\//) ? modelData.uri : ""
                        mono: true
                        maxLines: 2
                    }
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Card"
                title: BitwardenService.cardBrand !== ""
                    ? Tr.t("%1 details").arg(BitwardenService.cardBrand)
                    : Tr.t("Card details")

                BitwardenField {
                    visible: root.hasCardholder
                    label: Tr.t("Cardholder name")
                    value: root.entryData ? (root.entryData.cardholder_name ?? "") : ""
                    copyMode: "cardholder"
                }

                BitwardenField {
                    visible: root.hasCardNumber
                    label: Tr.t("Number")
                    value: root.entryData ? BitwardenService.cardNumber(root.entryData.number) : ""
                    maskedText: root.entryData ? BitwardenService.maskedCard(root.entryData.number) : ""
                    secretValue: true
                    revealKey: "card:number"
                    copyMode: "card-number"
                    mono: true
                    maxLines: 1
                }

                BitwardenField {
                    visible: root.hasCardExpiry
                    label: Tr.t("Expiration")
                    value: BitwardenService.cardExpiry
                    mono: true
                    maxLines: 1
                }

                BitwardenField {
                    visible: root.hasCardCode
                    label: Tr.t("Security code")
                    value: root.entryData ? (root.entryData.code ?? "") : ""
                    secretValue: true
                    revealKey: "card:code"
                    copyMode: "card-code"
                    mono: true
                    maxLines: 1
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Identity" && (BitwardenService.identityFullName !== "" || root.hasIdentityUsername)
                title: Tr.t("Personal details")

                BitwardenField {
                    visible: BitwardenService.identityFullName !== ""
                    label: Tr.t("Name")
                    value: BitwardenService.identityFullName
                    copyMode: "identity-name"
                }

                BitwardenField {
                    visible: root.hasIdentityUsername
                    label: Tr.t("Username")
                    value: root.entryData ? (root.entryData.username ?? "") : ""
                    copyMode: "username"
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Identity" && (root.hasSsn || root.hasPassport || root.hasLicense)
                title: Tr.t("Identification")

                BitwardenField {
                    visible: root.hasSsn
                    label: Tr.t("SSN")
                    value: root.entryData ? (root.entryData.ssn ?? "") : ""
                    secretValue: true
                    revealKey: "identity:ssn"
                    copyMode: "identity-ssn"
                }

                BitwardenField {
                    visible: root.hasPassport
                    label: Tr.t("Passport number")
                    value: root.entryData ? (root.entryData.passport_number ?? "") : ""
                    copyMode: "identity-passport"
                }

                BitwardenField {
                    visible: root.hasLicense
                    label: Tr.t("License number")
                    value: root.entryData ? (root.entryData.license_number ?? "") : ""
                    copyMode: "identity-license"
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Identity" && (root.hasEmail || root.hasPhone)
                title: Tr.t("Contact info")

                BitwardenField {
                    visible: root.hasEmail
                    label: Tr.t("Email")
                    value: root.entryData ? (root.entryData.email ?? "") : ""
                    copyMode: "identity-email"
                }

                BitwardenField {
                    visible: root.hasPhone
                    label: Tr.t("Phone")
                    value: root.entryData ? (root.entryData.phone ?? "") : ""
                    copyMode: "identity-phone"
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "Identity" && root.hasAddress
                title: Tr.t("Address")

                BitwardenField {
                    label: Tr.t("Address")
                    value: BitwardenService.identityAddress
                    copyMode: "identity-address"
                    maxLines: 6
                }
            }

            BitwardenSection {
                visible: root.loaded && root.type === "SSH Key"
                    && (root.hasSshPrivate || root.hasSshPublic || root.hasSshFingerprint)
                title: Tr.t("SSH key")

                BitwardenField {
                    visible: root.hasSshPrivate
                    label: Tr.t("Private key")
                    value: root.entryData ? (root.entryData.private_key ?? "") : ""
                    secretValue: true
                    revealKey: "ssh:private"
                    copyMode: "ssh-private"
                    mono: true
                    maxLines: 8
                }

                BitwardenField {
                    visible: root.hasSshPublic
                    label: Tr.t("Public key")
                    value: root.entryData ? (root.entryData.public_key ?? "") : ""
                    copyMode: "ssh-public"
                    mono: true
                    maxLines: 3
                }

                BitwardenField {
                    visible: root.hasSshFingerprint
                    label: Tr.t("Fingerprint")
                    value: root.entryData ? (root.entryData.fingerprint ?? "") : ""
                    copyMode: "ssh-fingerprint"
                    mono: true
                    maxLines: 2
                }
            }

            BitwardenSection {
                visible: root.loaded && BitwardenService.notes !== ""
                title: root.type === "Note" ? Tr.t("Secure note") : Tr.t("Additional options")

                BitwardenField {
                    label: Tr.t("Note")
                    value: BitwardenService.notes
                    copyMode: "notes"
                    maxLines: 10
                }
            }

            BitwardenSection {
                visible: root.loaded && BitwardenService.customFields.length > 0
                title: Tr.t("Custom fields")

                Repeater {
                    model: BitwardenService.customFields

                    BitwardenField {
                        required property var modelData

                        label: modelData.name
                        value: modelData.kind === "linked"
                            ? Tr.t("Linked to another field") : modelData.value
                        flag: modelData.kind === "boolean"
                        checked: modelData.value === "true"
                        secretValue: modelData.kind === "hidden"
                        revealKey: modelData.key
                        copyMode: modelData.kind === "text" || modelData.kind === "hidden"
                            ? modelData.mode : ""
                        copyLabel: modelData.name
                        maxLines: 6
                    }
                }
            }

            BitwardenSection {
                visible: root.loaded
                title: Tr.t("Item history")

                BitwardenField {
                    label: Tr.t("Password history")
                    value: Tr.t("%1 saved passwords").arg(BitwardenService.history.length)
                    maxLines: 1
                }

                Text {
                    Layout.fillWidth: true
                    visible: BitwardenService.history.length === 0
                    text: Tr.t("No previous passwords")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }

                Repeater {
                    model: BitwardenService.history

                    BitwardenField {
                        required property var modelData

                        label: modelData.date
                        value: modelData.password
                        secretValue: true
                        revealKey: modelData.key
                        copyMode: modelData.mode
                        copyLabel: Tr.t("Password")
                        maxLines: 1
                    }
                }
            }

            Item { Layout.preferredHeight: 2 }
        }
    }
}
