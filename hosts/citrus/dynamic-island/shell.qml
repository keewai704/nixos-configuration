pragma ComponentBehavior: Bound
import QtQuick
import QtCore as Core
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications

ShellRoot {
    id: root
    readonly property bool testing: Quickshell.env("ISLAND_TEST") === "1"
    property string page: ""
    property bool pinned: false
    property string targetScreen: ""
    property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    property var notice: null
    property string osd: ""
    property bool ready: false
    property alias preferences: preferences
    property alias history: history
    property alias clock: clock

    Core.Settings {
        id: preferences
        location: "file://" + (root.testing ? (Quickshell.env("ISLAND_TEST_SETTINGS") || "/tmp/dynamic-island-test.ini") : Quickshell.env("HOME") + "/.local/state/dynamic-island.ini")
        property bool notch: false
        property bool hover: true
        property bool dnd: false
        property bool reducedMotion: false
        property string accent: "#ebbcba"
    }
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
    ListModel {
        id: history
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: root.ready = true
    }
    Timer {
        id: osdTimer
        interval: 1800
        onTriggered: root.osd = ""
    }
    Timer {
        id: noticeTimer
        onTriggered: root.expireNotice()
    }
    function expireNotice() {
        const n = notice;
        notice = null;
        noticeTimer.stop();
        if (n && n.tracked)
            n.expire();
    }
    function dismissNotice() {
        const n = notice;
        notice = null;
        noticeTimer.stop();
        if (n && n.tracked)
            n.dismiss();
    }
    function showPage(next) {
        targetScreen = Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name || "";
        page = page === next && pinned ? "" : next;
        pinned = page !== "";
    }
    function close() {
        page = "";
        pinned = false;
    }
    function showOsd(label) {
        if (!ready)
            return;
        osd = label;
        osdTimer.restart();
    }
    function volume(value) {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, value));
    }
    function noctalia(args) {
        close();
        Quickshell.execDetached([Quickshell.env("ISLAND_NOCTALIA") || "noctalia", "msg"].concat(args));
    }
    Connections {
        target: root.sink?.audio || null
        function onVolumeChanged() {
            root.showOsd("Volume");
        }
        function onMutedChanged() {
            root.showOsd(root.sink.audio.muted ? "Muted" : "Volume");
        }
    }
    Connections {
        target: root.source?.audio || null
        function onMutedChanged() {
            root.showOsd(root.source.audio.muted ? "Mic muted" : "Mic on");
        }
    }
    Connections {
        target: root.notice
        function onTrackedChanged() {
            if (root.notice && !root.notice.tracked) {
                root.notice = null;
                noticeTimer.stop();
            }
        }
    }
    // Test instances never compete with the desktop notification owner.
    Loader {
        active: !root.testing || Quickshell.env("ISLAND_TEST_NOTIFICATIONS") === "1"
        sourceComponent: Component {
            NotificationServer {
                keepOnReload: true
                actionsSupported: true
                bodySupported: true
                bodyMarkupSupported: false
                onNotification: n => {
                    n.tracked = true;
                    for (let i = history.count - 1; i >= 0; --i)
                        if (history.get(i).notificationId === n.id)
                            history.remove(i);
                    history.insert(0, {
                        notificationId: n.id,
                        app: n.appName,
                        title: n.summary,
                        message: n.body,
                        time: Qt.formatDateTime(clock.date, "HH:mm")
                    });
                    if (history.count > 50)
                        history.remove(50, history.count - 50);
                    if (preferences.dnd && n.urgency !== NotificationUrgency.Critical) {
                        n.expire();
                        return;
                    }
                    if (root.notice && root.notice !== n)
                        root.expireNotice();
                    root.notice = n;
                    noticeTimer.stop();
                    if (n.expireTimeout !== 0 && n.urgency !== NotificationUrgency.Critical) {
                        noticeTimer.interval = n.expireTimeout < 0 ? 6000 : Math.max(1000, n.expireTimeout);
                        noticeTimer.restart();
                    }
                }
            }
        }
    }
    IpcHandler {
        target: "island"
        function toggle(): void {
            root.showPage("media");
        }
        function launcher(): void {
            root.showPage("launcher");
        }
        function calendar(): void {
            root.showPage("calendar");
        }
        function controls(): void {
            root.showPage("controls");
        }
        function notifications(): void {
            root.showPage("notifications");
        }
        function settings(): void {
            root.showPage("settings");
        }
        function session(): void {
            root.showPage("session");
        }
        function close(): void {
            root.close();
            root.dismissNotice();
        }
        function notch(): void {
            preferences.notch = !preferences.notch;
        }
        function status(): string {
            return JSON.stringify({
                page: root.page,
                pinned: root.pinned,
                notch: preferences.notch,
                player: root.player?.identity || "",
                notice: root.notice?.summary || "",
                notifications: history.count,
                audio: !!root.sink?.audio
            });
        }
    }
    Variants {
        model: Quickshell.screens
        Island {
            required property var modelData
            screen: modelData
            shell: root
        }
    }
}
