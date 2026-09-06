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
    readonly property var player: shell.player
    readonly property bool selected: !shell.targetScreen || shell.targetScreen === screen.name
    readonly property string page: selected ? shell.page : ""
    property bool hovered: false
    readonly property bool expanded: (selected && shell.pinned) || (prefs.hover && hovered)
    readonly property string stateName: page || (shell.notice ? "notice" : shell.osd ? "osd" : "media")
    readonly property bool large: expanded || page !== "" || !!shell.notice
    readonly property real availableWidth: Math.min(760, screen.width)
    property real expansion: large ? 1 : 0
    property real morph: prefs.notch ? 1 : 0
    readonly property int duration: prefs.reducedMotion ? 0 : 400
    readonly property var spring: Geometry.springCurve(0.8)
    readonly property var fade: Geometry.springCurve(1)
    readonly property color ink: "#efedf4"
    readonly property color muted: "#8e8996"
    readonly property color accent: prefs.accent
    property int calendarOffset: 0
    property int carouselOffset: 0
    readonly property date today: shell.clock.date
    readonly property date calendarMonth: new Date(today.getFullYear(), today.getMonth() + calendarOffset, 1)
    readonly property var apps: DesktopEntries.applications.values.filter(a => (a.name + " " + a.genericName + " " + a.comment).toLocaleLowerCase().includes(search.text.toLocaleLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
    property string confirmAction: ""

    anchors.top: true
    implicitWidth: availableWidth
    implicitHeight: Math.min(650, screen.height)
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "dynamic-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: selected && shell.pinned ? (page === "wallpaper" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
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
        onTriggered: window.hovered = false
    }

    component Label: Text {
        color: window.ink
        font.family: "Inter"
        font.pixelSize: 13
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Action: Button {
        id: action
        property bool active: false
        implicitWidth: Math.max(32, contentItem.implicitWidth + 20)
        implicitHeight: 32
        hoverEnabled: true
        Accessible.name: text
        background: Rectangle {
            radius: 10
            color: action.down ? "#39343e" : action.active ? "#30272e" : action.hovered || action.visualFocus ? "#222025" : "transparent"
            border.width: action.visualFocus ? 1 : 0
            border.color: window.accent
        }
        contentItem: Label {
            text: action.text
            color: action.active ? window.accent : window.ink
            opacity: action.enabled ? 1 : 0.3
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    component Level: Slider {
        id: slider
        from: 0
        to: 1
        implicitHeight: 30
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - 3
            width: slider.availableWidth
            height: 6
            radius: 3
            color: "#29262e"
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

    Item {
        id: surface
        x: (window.width - width) / 2
        y: 11 * (1 - window.morph) - 4 * window.morph
        width: Math.min(window.width - 32, window.large ? 619 : shell.osd ? 260 : 150)
        height: window.large ? (window.stateName === "media" ? 135 : window.stateName === "notice" ? 180 : window.stateName === "osd" ? 135 : window.stateName === "controls" ? 560 : 410) : 38
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
        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    leaveTimer.stop();
                    window.hovered = true;
                } else
                    leaveTimer.restart();
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: if (window.stateName === "media")
                shell.showPage("media")
            onWheel: wheel => shell.volume((shell.sink?.audio?.volume || 0) + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
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
                fillColor: "#000000"
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
            x: (surface.width - width) / 2 + window.expansion * (surface.width / 2 - 124)
            y: 10 + window.expansion * 18
            width: 100
            text: Qt.formatDateTime(window.today, "HH:mm")
            font.pixelSize: 14 + 10 * window.expansion
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
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
            anchors.margins: 18
            opacity: Math.max(0, Math.min(1, window.expansion))
            visible: opacity > 0.01
            enabled: window.large

            Item {
                anchors.fill: parent
                visible: window.stateName === "media"
                ClippingRectangle {
                    id: artwork
                    x: 0
                    y: 5
                    width: 88
                    height: 88
                    radius: 14
                    color: "#17151c"
                    Image {
                        anchors.fill: parent
                        source: window.player?.trackArtUrl || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "♫"
                        font.pixelSize: 34
                        color: window.accent
                        visible: !window.player?.trackArtUrl
                    }
                }
                Column {
                    x: 104
                    y: 7
                    width: Math.max(90, parent.width - 322)
                    spacing: 3
                    Label {
                        text: window.player?.trackTitle || (window.player?.isPlaying ? "Playing" : "Not playing")
                        font.weight: Font.DemiBold
                        width: parent.width
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                    Label {
                        text: window.player?.trackAlbum || ""
                        color: window.muted
                        width: parent.width
                        font.pixelSize: 11
                    }
                    Label {
                        text: window.player?.trackArtist || "Play music to see it here"
                        color: window.muted
                        width: parent.width
                        font.pixelSize: 11
                    }
                    Row {
                        spacing: 3
                        Action {
                            text: "⏮"
                            Accessible.name: "Previous track"
                            enabled: !!window.player?.canGoPrevious
                            onClicked: window.player.previous()
                        }
                        Action {
                            text: window.player?.isPlaying ? "⏸" : "▶"
                            Accessible.name: "Play/pause"
                            enabled: !!window.player?.canTogglePlaying
                            onClicked: window.player.togglePlaying()
                        }
                        Action {
                            text: "⏭"
                            Accessible.name: "Next track"
                            enabled: !!window.player?.canGoNext
                            onClicked: window.player.next()
                        }
                    }
                }
                Row {
                    x: parent.width - 204
                    y: 52
                    spacing: 1
                    Repeater {
                        model: 7
                        Column {
                            required property int index
                            readonly property date date: Geometry.dateOffset(window.today, index - 3 + window.carouselOffset)
                            width: 26
                            spacing: 3
                            opacity: index === 3 ? 1 : 0.22 + (3 - Math.abs(index - 3)) * 0.15
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.date.toLocaleDateString(Qt.locale("en_US"), "ddd").toUpperCase()
                                font.pixelSize: 9
                                color: parent.date.getDay() === 0 ? window.accent : window.muted
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.date.getDate()
                                font.pixelSize: index === 3 ? 17 : 13
                                font.bold: index === 3
                                color: parent.date.getDay() === 0 ? window.accent : window.ink
                            }
                        }
                    }
                }
                MouseArea {
                    x: parent.width - 204
                    y: 52
                    width: 190
                    height: 42
                    onClicked: shell.showPage("calendar")
                    onWheel: w => window.carouselOffset += w.angleDelta.y > 0 ? -1 : 1
                }
                Action {
                    anchors.right: parent.right
                    y: -12
                    text: "···"
                    implicitWidth: 26
                    implicitHeight: 26
                    Accessible.name: "Island menu"
                    onClicked: shell.showPage("controls")
                }
                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: shell.showPage("media")
                }
            }

            ColumnLayout {
                anchors.fill: parent
                visible: window.stateName !== "media" && window.stateName !== "osd" && window.stateName !== "notice"
                spacing: 12
                RowLayout {
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
                                label: "Notifications"
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
                        text: "×"
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
                    currentIndex: ["launcher", "calendar", "controls", "notifications", "settings", "session"].indexOf(window.page)
                    ColumnLayout {
                        spacing: 8
                        TextField {
                            id: search
                            Layout.fillWidth: true
                            placeholderText: "Search apps…"
                            color: window.ink
                            placeholderTextColor: window.muted
                            font.family: "Inter"
                            font.pixelSize: 16
                            background: Rectangle {
                                radius: 10
                                color: "#17151c"
                                border.color: search.activeFocus ? window.accent : "#29262e"
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
                                height: 48
                                background: Rectangle {
                                    radius: 10
                                    color: entry.hovered || entry.index === appList.currentIndex ? "#242027" : "transparent"
                                }
                                contentItem: RowLayout {
                                    IconImage {
                                        source: Quickshell.iconPath(entry.modelData.icon, "application-x-executable")
                                        implicitSize: 28
                                    }
                                    ColumnLayout {
                                        Label {
                                            text: entry.modelData.name
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: entry.modelData.genericName || entry.modelData.comment
                                            color: window.muted
                                            font.pixelSize: 10
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
                        RowLayout {
                            Action {
                                text: "‹"
                                Accessible.name: "Previous month"
                                onClicked: window.calendarOffset--
                            }
                            Label {
                                text: window.calendarMonth.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
                                font.pixelSize: 22
                                font.bold: true
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Action {
                                text: "Today"
                                onClicked: window.calendarOffset = 0
                            }
                            Action {
                                text: "›"
                                Accessible.name: "Next month"
                                onClicked: window.calendarOffset++
                            }
                        }
                        GridLayout {
                            columns: 7
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
                                        color: parent.isToday ? "#171218" : parent.modelData.getMonth() !== window.calendarMonth.getMonth() ? "#45404c" : window.ink
                                    }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 10
                        Label {
                            text: "Control center"
                            font.pixelSize: 22
                            font.bold: true
                        }
                        RowLayout {
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
                                text: shell.desktop.brightnessAvailable ? Math.round(shell.desktop.brightness) + "%" : "Unavailable"
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
                            Action {
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
                                width: 42
                            }
                        }
                        RowLayout {
                            Action {
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
                        }
                        RowLayout {
                            Action {
                                text: "Network"
                                onClicked: {
                                    shell.launch("network");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                text: "Bluetooth"
                                onClicked: {
                                    shell.launch("bluetooth");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                text: "Audio devices"
                                onClicked: {
                                    shell.launch("audio");
                                    window.hovered = false;
                                }
                            }
                            Action {
                                text: "Wallpaper"
                                onClicked: shell.showPage("wallpaper")
                            }
                        }
                        RowLayout {
                            Action {
                                text: "Clipboard"
                                onClicked: shell.showPage("clipboard")
                            }
                            Action {
                                text: "Windows"
                                onClicked: shell.showPage("windows")
                            }
                            Action {
                                text: shell.desktop.nightlight ? "Night light: On" : "Night light: Off"
                                active: shell.desktop.nightlight
                                onClicked: shell.desktop.run(["nightlight-toggle"])
                            }
                            Action {
                                text: "Lock"
                                onClicked: {
                                    shell.launch("lock");
                                    window.hovered = false;
                                }
                            }
                        }
                        RowLayout {
                            Label {
                                text: "Capture"
                                color: window.muted
                            }
                            Repeater {
                                model: ["region", "active", "all"]
                                Action {
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
                            visible: shell.desktop.powerProfiles.length > 0
                            Label {
                                text: "Power"
                                color: window.muted
                            }
                            Repeater {
                                model: shell.desktop.powerProfiles
                                Action {
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
                            Action {
                                text: shell.pinned ? "Pinned" : "Pin"
                                active: shell.pinned
                                onClicked: shell.pinned = !shell.pinned
                            }
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: SystemTray.items
                                Item {
                                    id: trayItem
                                    required property var modelData
                                    width: 32
                                    height: 32
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
                                        anchor.rect.x: surface.x + 18
                                        anchor.rect.y: surface.y + surface.height
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                    }
                    ColumnLayout {
                        RowLayout {
                            Label {
                                text: "Notification history"
                                font.pixelSize: 22
                                font.bold: true
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
                                height: content.implicitHeight + 20
                                radius: 12
                                color: "#17151c"
                                Column {
                                    id: content
                                    x: 12
                                    y: 10
                                    width: parent.width - 24
                                    spacing: 5
                                    Label {
                                        text: parent.parent.app + "  ·  " + parent.parent.time
                                        color: window.muted
                                        font.pixelSize: 10
                                        width: parent.width
                                    }
                                    Label {
                                        text: parent.parent.title
                                        font.bold: true
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
                            font.pixelSize: 22
                            font.bold: true
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
                        Row {
                            spacing: 12
                            Repeater {
                                model: ["#ebbcba", "#7aa2f7", "#a6da95", "#c6a0f6", "#f5a97f"]
                                Action {
                                    required property string modelData
                                    text: "●"
                                    active: prefs.accent === modelData
                                    contentItem: Label {
                                        text: "●"
                                        color: modelData
                                        font.pixelSize: 24
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    onClicked: prefs.accent = modelData
                                }
                            }
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
                            font.pixelSize: 22
                            font.bold: true
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
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ["wallpaper", "clipboard", "windows"].includes(window.page)
                    shell: window.shell
                    page: window.page
                    accent: window.accent
                    onDone: {
                        shell.close();
                        window.hovered = false;
                    }
                }
            }
            ColumnLayout {
                anchors.fill: parent
                visible: window.stateName === "notice"
                RowLayout {
                    Label {
                        text: shell.notice?.appName || "Notification"
                        color: window.accent
                        Layout.fillWidth: true
                    }
                    Action {
                        text: "×"
                        Accessible.name: "Dismiss notification"
                        onClicked: shell.dismissNotice()
                    }
                }
                Label {
                    text: shell.notice?.summary || ""
                    font.pixelSize: 17
                    font.bold: true
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
            width: parent.width - 36
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
                color: "#29262e"
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
                state: window.stateName
            });
        }
        function capture(path: string): void {
            if (shell.testing)
                surface.grabToImage(result => result.saveToFile(path));
        }
    }
}
