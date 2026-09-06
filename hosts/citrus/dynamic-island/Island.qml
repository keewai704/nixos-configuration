pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "Geometry.js" as Geometry

PanelWindow {
    id: window
    required property var shell
    readonly property var prefs: shell.preferences
    readonly property var theme: shell.theme
    readonly property var player: shell.player
    readonly property bool selected: !shell.targetScreen || shell.targetScreen === screen.name
    readonly property string page: selected ? shell.page : ""
    property bool hovered: false
    readonly property bool expanded: (selected && shell.pinned) || (prefs.hover && hovered)
    readonly property bool noticeVisible: !!shell.notice && !shell.noticeCollapsed
    readonly property string stateName: page || (noticeVisible ? "notice" : shell.osd ? "osd" : "media")
    readonly property bool large: (expanded && stateName !== "osd") || page !== "" || noticeVisible
    property int openMenus: 0
    readonly property bool popupOpen: desktopPages.dialogOpen || openMenus > 0
    onPopupOpenChanged: if (!popupOpen && !hovered)
        leaveTimer.restart()
    readonly property real availableWidth: Math.min(760, screen.width)
    property real expansion: large ? 1 : 0
    property real morph: prefs.notch ? 1 : 0
    readonly property int duration: prefs.reducedMotion ? 0 : 400
    readonly property var spring: Geometry.springCurve(0.8)
    readonly property var fade: Geometry.springCurve(1)
    readonly property color ink: theme.text
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent
    property int calendarOffset: 0
    property int carouselOffset: 0
    readonly property date today: shell.clock.date
    readonly property date calendarMonth: new Date(today.getFullYear(), today.getMonth() + calendarOffset, 1)
    readonly property var apps: DesktopEntries.applications.values.filter(a => (a.name + " " + a.genericName + " " + a.comment).toLocaleLowerCase().includes(search.text.toLocaleLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
    property string confirmAction: ""

    function updateHover(entered) {
        if (entered) {
            leaveTimer.stop();
            hovered = true;
        } else
            leaveTimer.restart();
    }

    anchors.top: true
    implicitWidth: availableWidth
    implicitHeight: Math.min(650, screen.height)
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "dynamic-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: !shell.testing && selected && shell.pinned ? (page === "wallpaper" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
    mask: Region {
        item: surface
    }

    Behavior on expansion {
        NumberAnimation {
            duration: window.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: window.spring
        }
    }
    Behavior on morph {
        NumberAnimation {
            duration: window.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: window.fade
        }
    }
    onPageChanged: {
        confirmAction = "";
        if (page === "launcher") {
            search.text = "";
            search.forceActiveFocus();
        } else if (page)
            surface.forceActiveFocus();
    }
    Timer {
        id: leaveTimer
        interval: 160
        onTriggered: {
            window.hovered = false;
            if (window.selected && !window.popupOpen)
                shell.collapse();
        }
    }

    component Label: Text {
        color: window.ink
        font.family: window.theme.fontFamily
        font.pixelSize: window.theme.fontSize
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Icon: Item {
        id: icon
        property string name: ""
        property color color: window.ink
        implicitWidth: 20
        implicitHeight: 20
        readonly property var paths: ({
                close: "M6 6L18 18M18 6L6 18",
                left: "M16 5L8 12L16 19",
                right: "M8 5L16 12L8 19",
                previous: "M6 5V19M18 5L8 12L18 19Z",
                next: "M18 5V19M6 5L16 12L6 19Z",
                play: "M8 5L19 12L8 19Z",
                pause: "M8 5V19M16 5V19",
                music: "M10 17.5V6L20 4V15.5M10 9L20 7M10 17.5A3 2.5 0 1 1 4 17.5A3 2.5 0 1 1 10 17.5M20 15.5A3 2.5 0 1 1 14 15.5A3 2.5 0 1 1 20 15.5",
                more: "M5 12H5.1M12 12H12.1M19 12H19.1"
            })
        Shape {
            anchors.centerIn: parent
            preferredRendererType: Shape.CurveRenderer
            width: 24
            height: 24
            scale: Math.min(icon.width, icon.height) / 24
            ShapePath {
                strokeColor: icon.color
                strokeWidth: icon.name === "more" ? 3 : 1.8
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                fillColor: icon.name === "play" ? icon.color : "transparent"
                PathSvg {
                    path: icon.paths[icon.name] || ""
                }
            }
        }
    }
    component Action: Button {
        id: action
        property bool active: false
        property bool filled: false
        property string glyph: ""
        property int textAlignment: Qt.AlignHCenter
        implicitWidth: glyph ? 36 : Math.max(36, contentItem.implicitWidth + 24)
        implicitHeight: 36
        horizontalPadding: glyph ? 8 : 12
        verticalPadding: 8
        hoverEnabled: true
        Accessible.name: text
        background: Rectangle {
            radius: 10
            color: action.down ? window.theme.border : action.active || action.hovered || action.visualFocus ? window.theme.hover : action.filled ? window.theme.surface : "transparent"
            border.width: action.visualFocus ? 1 : 0
            border.color: window.accent
        }
        contentItem: Item {
            implicitWidth: action.glyph ? 20 : actionLabel.implicitWidth
            implicitHeight: 20
            opacity: action.enabled ? 1 : 0.3
            Label {
                id: actionLabel
                anchors.fill: parent
                visible: !action.glyph
                text: action.text
                color: action.active ? window.accent : window.ink
                horizontalAlignment: action.textAlignment
                verticalAlignment: Text.AlignVCenter
            }
            Icon {
                anchors.centerIn: parent
                visible: !!action.glyph
                name: action.glyph
                color: action.active ? window.accent : window.ink
            }
        }
    }
    component Level: Slider {
        id: slider
        from: 0
        to: 1
        implicitHeight: 36
        padding: 0
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - 3
            width: slider.availableWidth
            height: 6
            radius: 3
            color: window.theme.border
            Rectangle {
                width: slider.visualPosition * parent.width
                height: 6
                radius: 3
                color: window.accent
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: window.ink
            border.width: slider.visualFocus ? 2 : 0
            border.color: window.accent
        }
    }

    MouseArea {
        id: surface
        acceptedButtons: Qt.LeftButton
        hoverEnabled: !shell.testing
        onContainsMouseChanged: if (!shell.testing)
            window.updateHover(containsMouse)
        onClicked: if (window.stateName === "media")
            shell.showPage("media")
        onWheel: wheel => shell.volume((shell.sink?.audio?.volume || 0) + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
        x: (window.width - width) / 2
        y: 11 * (1 - window.morph) - 4 * window.morph
        width: Math.min(window.width - 32, window.large ? 640 : shell.osd ? 260 : 150)
        height: window.large ? (window.stateName === "media" ? Math.max(152, mediaDetails.implicitHeight + 40) : window.stateName === "notice" ? noticeContent.implicitHeight + 40 : window.stateName === "controls" ? Math.min(window.height - 32, controlsPage.implicitHeight + navigation.implicitHeight + 52) : 410) : 38
        focus: true
        Keys.onEscapePressed: {
            shell.close();
            window.hovered = false;
            shell.dismissNotice();
        }
        Behavior on width {
            NumberAnimation {
                duration: window.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: window.spring
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: window.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: window.spring
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: {
                shell.close();
                window.hovered = false;
                shell.dismissNotice();
            }
        }
        Shape {
            id: silhouette
            anchors.fill: parent
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: window.theme.background
                PathSvg {
                    path: Geometry.outline(surface.width, surface.height, window.morph, 14, 19 + 9 * window.expansion)
                }
            }
        }
        MultiEffect {
            anchors.fill: silhouette
            source: silhouette
            shadowEnabled: true
            shadowColor: "#88000000"
            shadowBlur: 0.7
            shadowVerticalOffset: 6
        }
        // A single clock travels from the pill centre to the expanded right column.
        Label {
            id: time
            x: (surface.width - width) / 2 + window.expansion * (surface.width / 2 - 118)
            y: 3 + window.expansion * ((surface.height - 84) / 2 - 3)
            width: 100
            height: 32
            text: Qt.formatDateTime(window.today, "HH:mm")
            font.pixelSize: window.theme.fontSize + 1 + 10 * window.expansion
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: window.stateName === "media" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: window.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: window.fade
                }
            }
            TapHandler {
                onTapped: shell.showPage("calendar")
            }
        }
        Row {
            x: surface.width - 35
            y: 11
            spacing: 2
            visible: !window.large && !shell.osd && !!window.player?.isPlaying
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    width: 3
                    height: 5
                    radius: 1.5
                    color: window.accent
                    y: (16 - height) / 2
                    // Playback indicator, matching the video's four bars; not a spectrum analyser.
                    SequentialAnimation on height {
                        running: !!window.player?.isPlaying && !window.large && !prefs.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 6 + index * 3
                            duration: 180 + index * 50
                        }
                        NumberAnimation {
                            to: 3
                            duration: 260 - index * 35
                        }
                    }
                }
            }
        }
        Item {
            id: expandedContent
            anchors.fill: parent
            anchors.margins: 20
            opacity: Math.max(0, Math.min(1, window.expansion))
            visible: opacity > 0.01
            enabled: window.large

            RowLayout {
                id: mediaContent
                anchors.fill: parent
                spacing: 20
                visible: window.stateName === "media"
                ClippingRectangle {
                    id: artwork
                    Layout.preferredWidth: 112
                    Layout.preferredHeight: 112
                    Layout.alignment: Qt.AlignVCenter
                    radius: 14
                    color: window.theme.surface
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: window.player?.trackArtUrl || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        name: "music"
                        color: window.accent
                        visible: cover.status !== Image.Ready
                    }
                }
                ColumnLayout {
                    id: mediaDetails
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                    Label {
                        text: window.player?.trackTitle || (window.player?.isPlaying ? "Playing" : "Not playing")
                        font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                    Label {
                        visible: !!text
                        text: window.player?.trackAlbum || ""
                        color: window.muted
                        Layout.fillWidth: true
                        font.pixelSize: Math.max(11, window.theme.fontSize - 2)
                    }
                    Label {
                        text: window.player?.trackArtist || "Play music to see it here"
                        color: window.muted
                        Layout.fillWidth: true
                        font.pixelSize: Math.max(11, window.theme.fontSize - 2)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Action {
                            glyph: "previous"
                            Accessible.name: "Previous track"
                            enabled: !!window.player?.canGoPrevious
                            onClicked: window.player.previous()
                        }
                        Action {
                            glyph: window.player?.isPlaying ? "pause" : "play"
                            Accessible.name: "Play/pause"
                            enabled: !!window.player?.canTogglePlaying
                            onClicked: window.player.togglePlaying()
                        }
                        Action {
                            glyph: "next"
                            Accessible.name: "Next track"
                            enabled: !!window.player?.canGoNext
                            onClicked: window.player.next()
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Action {
                            glyph: "more"
                            Accessible.name: "Island menu"
                            onClicked: shell.showPage("controls")
                        }
                    }
                }
                Item {
                    Layout.preferredWidth: 196
                    Layout.fillHeight: true
                    Row {
                        id: week
                        y: (parent.height - 84) / 2 + 44
                        spacing: 0
                        Repeater {
                            model: 7
                            Column {
                                required property int index
                                readonly property date date: Geometry.dateOffset(window.today, index - 3 + window.carouselOffset)
                                width: 28
                                spacing: 4
                                opacity: index === 3 ? 1 : 0.22 + (3 - Math.abs(index - 3)) * 0.15
                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: parent.date.toLocaleDateString(Qt.locale("en_US"), "ddd").toUpperCase()
                                    font.pixelSize: Math.max(9, window.theme.fontSize - 4)
                                    color: parent.date.getDay() === 0 ? window.accent : window.muted
                                }
                                Label {
                                    width: parent.width
                                    height: 22
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: parent.date.getDate()
                                    font.pixelSize: index === 3 ? window.theme.fontSize + 4 : window.theme.fontSize
                                    font.bold: index === 3
                                    color: parent.date.getDay() === 0 ? window.accent : window.ink
                                }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: week
                        onClicked: shell.showPage("calendar")
                        onWheel: w => window.carouselOffset += w.angleDelta.y > 0 ? -1 : 1
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                visible: window.stateName !== "media" && window.stateName !== "osd" && window.stateName !== "notice"
                spacing: 12
                RowLayout {
                    id: navigation
                    spacing: 4
                    Layout.fillWidth: true
                    Repeater {
                        model: [
                            {
                                key: "launcher",
                                label: "Apps"
                            },
                            {
                                key: "calendar",
                                label: "Calendar"
                            },
                            {
                                key: "controls",
                                label: "Controls"
                            },
                            {
                                key: "notifications",
                                label: "History"
                            },
                            {
                                key: "settings",
                                label: "Settings"
                            },
                            {
                                key: "session",
                                label: "Power"
                            }
                        ]
                        Action {
                            required property var modelData
                            text: modelData.label
                            active: window.page === modelData.key
                            onClicked: {
                                shell.page = modelData.key;
                                shell.pinned = true;
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Action {
                        glyph: "close"
                        Accessible.name: "Close"
                        onClicked: {
                            shell.close();
                            window.hovered = false;
                        }
                    }
                }
                StackLayout {
                    visible: currentIndex >= 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    Layout.minimumWidth: 0
                    currentIndex: ["launcher", "calendar", "controls", "notifications", "settings", "session"].indexOf(window.page)
                    ColumnLayout {
                        spacing: 8
                        TextField {
                            id: search
                            implicitHeight: 40
                            leftPadding: 12
                            rightPadding: 12
                            topPadding: 10
                            bottomPadding: 10
                            Layout.fillWidth: true
                            placeholderText: "Search apps…"
                            color: window.ink
                            placeholderTextColor: window.muted
                            font.family: window.theme.fontFamily
                            font.pixelSize: window.theme.fontSize + 3
                            background: Rectangle {
                                radius: 10
                                color: window.theme.surface
                                border.color: search.activeFocus ? window.accent : window.theme.border
                            }
                            onTextChanged: appList.currentIndex = 0
                            Keys.onDownPressed: appList.currentIndex = Math.min(appList.count - 1, appList.currentIndex + 1)
                            Keys.onUpPressed: appList.currentIndex = Math.max(0, appList.currentIndex - 1)
                            onAccepted: if (window.apps[appList.currentIndex]) {
                                window.apps[appList.currentIndex].execute();
                                shell.close();
                                window.hovered = false;
                            }
                        }
                        ListView {
                            id: appList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: window.apps
                            spacing: 3
                            delegate: ItemDelegate {
                                id: entry
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 56
                                horizontalPadding: 12
                                verticalPadding: 8
                                background: Rectangle {
                                    radius: 10
                                    color: entry.hovered || entry.index === appList.currentIndex ? window.theme.hover : "transparent"
                                }
                                contentItem: RowLayout {
                                    spacing: 12
                                    IconImage {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        Layout.alignment: Qt.AlignVCenter
                                        source: Quickshell.iconPath(entry.modelData.icon, "application-x-executable")
                                        implicitSize: 28
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 2
                                        Label {
                                            text: entry.modelData.name
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            visible: !!text
                                            text: entry.modelData.genericName || entry.modelData.comment
                                            color: window.muted
                                            font.pixelSize: Math.max(10, window.theme.fontSize - 3)
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                onClicked: {
                                    modelData.execute();
                                    shell.close();
                                    window.hovered = false;
                                }
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: appList.count === 0
                                text: "No matching apps"
                                color: window.muted
                            }
                        }
                    }
                    ColumnLayout {
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            Action {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "left"
                                Accessible.name: "Previous month"
                                onClicked: window.calendarOffset--
                            }
                            Label {
                                anchors.centerIn: parent
                                width: parent.width - 200
                                text: window.calendarMonth.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
                                font.pixelSize: window.theme.fontSize + 9
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Action {
                                    text: "Today"
                                    onClicked: window.calendarOffset = 0
                                }
                                Action {
                                    glyph: "right"
                                    Accessible.name: "Next month"
                                    onClicked: window.calendarOffset++
                                }
                            }
                        }
                        GridLayout {
                            columns: 7
                            uniformCellWidths: true
                            rowSpacing: 2
                            columnSpacing: 4
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Repeater {
                                model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
                                Label {
                                    required property string modelData
                                    text: modelData
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    color: window.muted
                                }
                            }
                            Repeater {
                                model: Geometry.monthCells(window.calendarMonth.getFullYear(), window.calendarMonth.getMonth())
                                Rectangle {
                                    required property var modelData
                                    readonly property bool isToday: modelData.toDateString() === window.today.toDateString()
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    color: isToday ? window.accent : "transparent"
                                    Label {
                                        anchors.centerIn: parent
                                        text: parent.modelData.getDate()
                                        color: parent.isToday ? window.theme.onAccent : parent.modelData.getMonth() !== window.calendarMonth.getMonth() ? window.theme.muted : window.ink
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        id: controlsPage
                        spacing: 10
                        Label {
                            text: "Control center"
                            font.pixelSize: window.theme.fontSize + 9
                            font.weight: Font.Medium
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Label {
                                text: "Brightness"
                                Layout.preferredWidth: 100
                            }
                            Level {
                                Layout.fillWidth: true
                                enabled: shell.desktop.brightnessAvailable
                                value: shell.desktop.brightness / 100
                                Accessible.name: "Display brightness"
                                onMoved: shell.desktop.run(["brightness-set", Math.round(value * 100)])
                            }
                            Label {
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignRight
                                text: shell.desktop.brightnessAvailable ? Math.round(shell.desktop.brightness) + "%" : "—"
                            }
                        }
                        Label {
                            visible: !!shell.desktop.brightnessError
                            text: shell.desktop.brightnessError
                            color: window.accent
                            Layout.fillWidth: true
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Label {
                            text: shell.sink?.description || "No audio output"
                            color: window.muted
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Action {
                                Layout.preferredWidth: 100
                                textAlignment: Qt.AlignLeft
                                horizontalPadding: 0
                                text: shell.sink?.audio?.muted ? "Muted" : "Volume"
                                enabled: !!shell.sink?.audio
                                onClicked: shell.sink.audio.muted = !shell.sink.audio.muted
                            }
                            Level {
                                Layout.fillWidth: true
                                enabled: !!shell.sink?.audio
                                value: shell.sink?.audio?.volume || 0
                                Accessible.name: "Volume"
                                onMoved: shell.volume(value)
                            }
                            Label {
                                text: Math.round((shell.sink?.audio?.volume || 0) * 100) + "%"
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Action {
                                Layout.preferredWidth: 100
                                textAlignment: Qt.AlignLeft
                                horizontalPadding: 0
                                text: shell.source?.audio?.muted ? "Mic muted" : "Microphone"
                                enabled: !!shell.source?.audio
                                onClicked: shell.source.audio.muted = !shell.source.audio.muted
                            }
                            Level {
                                Layout.fillWidth: true
                                enabled: !!shell.source?.audio
                                value: shell.source?.audio?.volume || 0
                                Accessible.name: "Microphone volume"
                                onMoved: shell.source.audio.volume = value
                            }
                            Label {
                                text: Math.round((shell.source?.audio?.volume || 0) * 100) + "%"
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignRight
                                opacity: shell.source?.audio ? 1 : 0.3
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            uniformCellWidths: true
                            columnSpacing: 8
                            rowSpacing: 8
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Network"
                                onClicked: {
                                    shell.launch("network");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Bluetooth"
                                onClicked: {
                                    shell.launch("bluetooth");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Audio devices"
                                onClicked: {
                                    shell.launch("audio");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Wallpaper"
                                onClicked: shell.showPage("wallpaper")
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Clipboard"
                                onClicked: shell.showPage("clipboard")
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Windows"
                                onClicked: shell.showPage("windows")
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: shell.desktop.nightlight ? "Night light: On" : "Night light: Off"
                                active: shell.desktop.nightlight
                                onClicked: shell.desktop.run(["nightlight-toggle"])
                            }
                            Action {
                                Layout.fillWidth: true
                                filled: true
                                text: "Lock"
                                onClicked: {
                                    shell.launch("lock");
                                    window.hovered = false;
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Label {
                                Layout.preferredWidth: 100
                                text: "Capture"
                                color: window.muted
                            }
                            Repeater {
                                model: ["region", "active", "all"]
                                Action {
                                    Layout.fillWidth: true
                                    filled: true
                                    required property string modelData
                                    text: modelData === "region" ? "Region" : modelData === "active" ? "Window" : "All screens"
                                    onClicked: {
                                        shell.launch("screenshot-" + modelData);
                                        window.hovered = false;
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: shell.desktop.powerProfiles.length > 0
                            Label {
                                Layout.preferredWidth: 100
                                text: "Power"
                                color: window.muted
                            }
                            Repeater {
                                model: shell.desktop.powerProfiles
                                Action {
                                    Layout.fillWidth: true
                                    filled: true
                                    required property string modelData
                                    text: modelData
                                    active: shell.desktop.powerProfile === modelData
                                    onClicked: shell.desktop.run(["power-set", modelData])
                                }
                            }
                        }
                        Label {
                            visible: !!shell.desktop.error && !shell.desktop.brightnessError
                            text: shell.desktop.error
                            color: window.accent
                            Layout.fillWidth: true
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        RowLayout {
                            Action {
                                text: prefs.dnd ? "Notifications off" : "Notifications on"
                                active: prefs.dnd
                                onClicked: prefs.dnd = !prefs.dnd
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                        }
                        Row {
                            visible: SystemTray.items.values.length > 0
                            spacing: 8
                            Repeater {
                                model: SystemTray.items
                                Item {
                                    id: trayItem
                                    required property var modelData
                                    width: 36
                                    height: 36
                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: 22
                                        source: parent.modelData.icon
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: mouse => {
                                            if (mouse.button === Qt.LeftButton)
                                                parent.modelData.activate();
                                            else if (parent.modelData.hasMenu)
                                                trayMenu.open();
                                        }
                                    }
                                    QsMenuAnchor {
                                        id: trayMenu
                                        menu: trayItem.modelData.menu
                                        anchor.window: window
                                        anchor.rect.x: surface.x + trayItem.mapToItem(surface, 0, 0).x
                                        anchor.rect.y: surface.y + trayItem.mapToItem(surface, 0, 0).y + trayItem.height
                                        onOpened: window.openMenus++
                                        onClosed: window.openMenus--
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        RowLayout {
                            Label {
                                text: "Notification history"
                                font.pixelSize: window.theme.fontSize + 9
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Action {
                                text: "Clear"
                                enabled: shell.history.count > 0
                                onClicked: shell.history.clear()
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 8
                            model: shell.history
                            delegate: Rectangle {
                                required property string app
                                required property string title
                                required property string message
                                required property string time
                                width: ListView.view.width
                                height: content.implicitHeight + 24
                                radius: 12
                                color: window.theme.surface
                                Column {
                                    id: content
                                    x: 12
                                    y: 12
                                    width: parent.width - 24
                                    spacing: 5
                                    Label {
                                        text: parent.parent.app + "  ·  " + parent.parent.time
                                        color: window.muted
                                        font.pixelSize: Math.max(10, window.theme.fontSize - 3)
                                        width: parent.width
                                    }
                                    Label {
                                        text: parent.parent.title
                                        font.weight: Font.Medium
                                        width: parent.width
                                    }
                                    Label {
                                        text: parent.parent.message
                                        color: window.muted
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        width: parent.width
                                    }
                                }
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: shell.history.count === 0
                                text: "No notifications yet"
                                color: window.muted
                            }
                        }
                    }
                    ColumnLayout {
                        Label {
                            text: "Island settings"
                            font.pixelSize: window.theme.fontSize + 9
                            font.weight: Font.Medium
                        }
                        Action {
                            text: prefs.notch ? "Notch at top edge" : "Floating pill (11px)"
                            active: prefs.notch
                            onClicked: prefs.notch = !prefs.notch
                        }
                        Action {
                            text: prefs.hover ? "Hover to expand: On" : "Hover to expand: Off"
                            active: prefs.hover
                            onClicked: prefs.hover = !prefs.hover
                        }
                        Action {
                            text: prefs.reducedMotion ? "Animation: Off" : "Animation: 400 ms / spring"
                            onClicked: prefs.reducedMotion = !prefs.reducedMotion
                        }
                        Label {
                            text: "Colors and typography follow Stylix."
                            color: window.accent
                            Layout.fillWidth: true
                        }
                        Label {
                            text: window.theme.fontFamily
                            color: window.muted
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "Changes save automatically. Right-click or press Esc to close."
                            color: window.muted
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                    }
                    ColumnLayout {
                        Label {
                            text: "Session"
                            font.pixelSize: window.theme.fontSize + 9
                            font.weight: Font.Medium
                        }
                        Action {
                            text: "Lock"
                            onClicked: {
                                shell.close();
                                shell.launch("lock");
                                window.hovered = false;
                            }
                        }
                        Repeater {
                            model: [
                                {
                                    label: "Suspend",
                                    cmd: "suspend"
                                },
                                {
                                    label: "Restart",
                                    cmd: "reboot"
                                },
                                {
                                    label: "Power off",
                                    cmd: "poweroff"
                                }
                            ]
                            Action {
                                required property var modelData
                                text: window.confirmAction === modelData.cmd ? "Run " + modelData.label + "?" : modelData.label
                                active: window.confirmAction === modelData.cmd
                                onClicked: {
                                    if (window.confirmAction !== modelData.cmd)
                                        window.confirmAction = modelData.cmd;
                                    else {
                                        shell.close();
                                        Quickshell.execDetached(["systemctl", modelData.cmd]);
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
                DesktopPages {
                    id: desktopPages
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ["wallpaper", "clipboard", "windows"].includes(window.page)
                    shell: window.shell
                    page: window.page
                    onDone: {
                        shell.close();
                        window.hovered = false;
                    }
                }
            }
            ColumnLayout {
                id: noticeContent
                anchors.fill: parent
                visible: window.stateName === "notice"
                RowLayout {
                    Label {
                        text: shell.notice?.appName || "Notification"
                        color: window.accent
                        Layout.fillWidth: true
                    }
                    Action {
                        glyph: "close"
                        Accessible.name: "Dismiss notification"
                        onClicked: shell.dismissNotice()
                    }
                }
                Label {
                    text: shell.notice?.summary || ""
                    font.pixelSize: 17
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }
                Label {
                    text: shell.notice?.body || ""
                    color: window.muted
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
                Row {
                    spacing: 8
                    Repeater {
                        model: shell.notice?.actions || []
                        Action {
                            required property var modelData
                            text: modelData.text
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }
        }
        RowLayout {
            anchors.centerIn: parent
            width: parent.width - 40
            visible: window.stateName === "osd" && !window.page
            Label {
                text: shell.osd
                color: window.accent
                Layout.fillWidth: shell.osdValue < 0
            }
            Rectangle {
                visible: shell.osdValue >= 0
                Layout.fillWidth: true
                height: 5
                radius: 3
                color: window.theme.border
                Rectangle {
                    width: parent.width * Math.min(1, Math.max(0, shell.osdValue))
                    height: 5
                    radius: 3
                    color: window.ink
                }
            }
            Label {
                visible: shell.osdValue >= 0
                text: Math.round(shell.osdValue * 100) + "%"
            }
        }
    }
    IpcHandler {
        target: "island-view-" + window.screen.name
        function geometry(): string {
            return JSON.stringify({
                width: surface.width,
                height: surface.height,
                y: surface.y,
                state: window.stateName,
                expanded: window.expanded,
                hovered: window.hovered,
                popupOpen: window.popupOpen
            });
        }
        function capture(path: string): void {
            if (shell.testing)
                surface.grabToImage(result => result.saveToFile(path));
        }
    }
}
