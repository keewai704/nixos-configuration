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
    property var players: Mpris.players.values
    property string preferredPlayer: ""
    property var player: selectPlayer(players, preferredPlayer)
    readonly property var playerOptions: [
        {
            name: "Automatic",
            key: ""
        }
    ].concat(players.filter(p => p.canPlay || p.isPlaying || p.trackTitle?.trim()).map(p => ({
                name: p.identity,
                key: p.dbusName
            })))
    onPlayersChanged: if (preferredPlayer && !players.some(p => p.dbusName === preferredPlayer))
        preferredPlayer = ""
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    property var notices: []
    // Keep arrival order in the queue while giving critical notifications the display.
    readonly property var notice: notices.find(n => n.urgency === NotificationUrgency.Critical) || notices[0] || null
    readonly property bool criticalNotice: notice?.urgency === NotificationUrgency.Critical
    onCriticalNoticeChanged: if (criticalNotice)
        noticeCollapsed = false
    property bool noticeCollapsed: false
    property int noticeReaders: 0
    property int unreadCount: 0
    function recountUnread() {
        let count = 0;
        for (let i = 0; i < history.count; ++i)
            if (history.get(i).unread)
                count++;
        unreadCount = count;
    }
    property string osd: ""
    property real osdValue: -1
    property bool ready: false
    property alias preferences: preferences
    property alias history: history
    property alias clock: clock
    property alias desktop: desktop
    property alias theme: theme

    Theme {
        id: theme
    }

    function selectPlayer(players, preferred) {
        return players.find(p => preferred && p.dbusName === preferred) || players.find(p => p.isPlaying) || players.find(p => p.playbackState === MprisPlaybackState.Paused && p.trackTitle?.trim()) || null;
    }
    function seekTo(position) {
        if (player?.canSeek && player.positionSupported && player.lengthSupported && player.length > 0 && Number.isFinite(position))
            player.position = Math.max(0, Math.min(player.length, position));
    }
    function markHistoryRead() {
        for (let i = 0; i < history.count; ++i)
            history.setProperty(i, "unread", false);
        recountUnread();
    }

    Desktop {
        id: desktop
        testing: root.testing
        onFeedback: (message, value) => root.showOsd(message, value)
    }
    onPageChanged: {
        desktop.refresh(page);
        if (page === "notifications")
            markHistoryRead();
        updateNoticeTimer();
    }

    Core.Settings {
        id: preferences
        location: "file://" + (root.testing ? (Quickshell.env("ISLAND_TEST_SETTINGS") || "/tmp/dynamic-island-test.ini") : Quickshell.env("HOME") + "/.local/state/dynamic-island.ini")
        property bool notch: false
        property bool hover: true
        property bool dnd: false
        property bool reducedMotion: false
    }
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
    ListModel {
        id: history
        onCountChanged: root.recountUnread()
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
    function updateNoticeTimer() {
        noticeTimer.stop();
        if (notice && notice.urgency !== NotificationUrgency.Critical && notice.expireTimeout !== 0 && !page && noticeReaders === 0) {
            noticeTimer.interval = notice.expireTimeout > 0 ? Math.max(1000, notice.expireTimeout) : 6000;
            noticeTimer.start();
        }
    }
    onNoticeReadersChanged: updateNoticeTimer()
    onNoticeChanged: {
        noticeCollapsed = false;
        // Reset the full viewing time when a queued notification reaches the front.
        updateNoticeTimer();
    }
    function expireNotice() {
        if (notice?.tracked)
            notice.expire();
    }
    function dismissNotice() {
        if (notice?.tracked)
            notice.dismiss();
    }
    function recordNotice(n) {
        for (let i = history.count - 1; i >= 0; --i)
            if (history.get(i).notificationId === n.id)
                history.remove(i);
        if (!n.transient) {
            history.insert(0, {
                notificationId: n.id,
                app: n.appName,
                title: n.summary,
                message: n.body,
                time: Qt.formatDateTime(clock.date, "HH:mm"),
                unread: page !== "notifications"
            });
            if (history.count > 50)
                history.remove(50, history.count - 50);
        }
        recountUnread();
    }
    function enqueueNotice(n) {
        recordNotice(n);
        n.tracked = true;
        if (preferences.dnd && n.urgency !== NotificationUrgency.Critical) {
            n.expire();
            return;
        }
        if (notices.includes(n)) {
            updateNoticeTimer();
            return;
        }
        n.closed.connect(() => {
            root.notices = root.notices.filter(item => item !== n);
            if (!root.notice && root.page === "notice")
                root.close();
        });
        // Quickshell updates replacements in place without emitting onNotification.
        // Coalesce their property signals so history and priority see the whole update.
        const refresh = () => {
            if (!root.notices.includes(n))
                return;
            root.recordNotice(n);
            if (preferences.dnd && n.urgency !== NotificationUrgency.Critical) {
                n.expire();
                return;
            }
            if (root.notice === n)
                root.updateNoticeTimer();
        };
        for (const signal of [n.summaryChanged, n.bodyChanged, n.appNameChanged, n.transientChanged, n.urgencyChanged, n.expireTimeoutChanged])
            signal.connect(() => Qt.callLater(refresh));
        root.notices = notices.concat([n]);
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
    function collapse() {
        close();
        noticeCollapsed = true;
    }
    function showOsd(label, value) {
        if (!ready)
            return;
        osd = label;
        osdValue = value === undefined ? (sink?.audio?.volume || 0) : value;
        osdTimer.restart();
    }
    function volume(value) {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, value));
    }
    function launch(action) {
        close();
        desktop.run([action]);
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
            root.showOsd(root.source.audio.muted ? "Mic muted" : "Mic on", root.source.audio.volume);
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
                onNotification: n => root.enqueueNotice(n)
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
        function wallpaper(): void {
            root.showPage("wallpaper");
        }
        function clipboard(): void {
            root.showPage("clipboard");
        }
        function windows(): void {
            root.showPage("windows");
        }
        function lock(): void {
            root.launch("lock");
        }
        function brightnessUp(): void {
            desktop.run(["brightness-up"]);
        }
        function brightnessDown(): void {
            desktop.run(["brightness-down"]);
        }
        function volumeUp(): void {
            root.volume((root.sink?.audio?.volume || 0) + 0.05);
        }
        function volumeDown(): void {
            root.volume((root.sink?.audio?.volume || 0) - 0.05);
        }
        function mute(): void {
            if (root.sink?.audio)
                root.sink.audio.muted = !root.sink.audio.muted;
        }
        function micMute(): void {
            if (root.source?.audio)
                root.source.audio.muted = !root.source.audio.muted;
        }
        function playPause(): void {
            if (root.player?.canTogglePlaying)
                root.player.togglePlaying();
        }
        function next(): void {
            if (root.player?.canGoNext)
                root.player.next();
        }
        function previous(): void {
            if (root.player?.canGoPrevious)
                root.player.previous();
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
                pendingNotices: root.notices.length,
                notifications: history.count,
                unread: root.unreadCount,
                preferredPlayer: root.preferredPlayer,
                audio: !!root.sink?.audio,
                desktopBusy: desktop.busy,
                desktopError: desktop.error,
                brightness: desktop.brightness,
                brightnessAvailable: desktop.brightnessAvailable,
                clipboardCount: desktop.clipboard.length,
                windowCount: desktop.windows.length,
                wallpaperCount: desktop.wallpapers.length,
                theme: {
                    background: theme.background.toString(),
                    accent: theme.accent.toString(),
                    fontFamily: theme.fontFamily,
                    fontSize: theme.fontSize
                }
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
