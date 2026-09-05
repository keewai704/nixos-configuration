pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: desktop
    required property bool testing
    property real brightness: 0
    property bool brightnessAvailable: false
    property string brightnessError: ""
    property string wallpaper: ""
    property var wallpapers: []
    property var clipboard: []
    property var windows: []
    property bool nightlight: false
    property string powerProfile: ""
    property var powerProfiles: []
    property string error: ""
    property var queue: []
    readonly property bool busy: worker.running || queue.length > 0
    signal feedback(string message, real value)

    function run(args) {
        if (testing && !Quickshell.env("ISLAND_TEST_ACTION"))
            return;
        error = "";
        // Coalesce slider updates while DDC is busy; discrete key presses retain order.
        if (args[0] === "brightness-set")
            queue = queue.filter(a => a[0] !== "brightness-set");
        queue = queue.concat([args.map(String)]);
        pump();
    }
    function pump() {
        if (worker.running || !queue.length)
            return;
        const args = queue[0];
        queue = queue.slice(1);
        worker.action = args[0];
        worker.command = [testing ? Quickshell.env("ISLAND_TEST_ACTION") : (Quickshell.env("ISLAND_ACTION") || "island-action")].concat(args);
        worker.running = true;
    }
    function refresh(page) {
        if (page === "controls") {
            run(["brightness-status"]);
            run(["nightlight-status"]);
            run(["power-status"]);
        } else if (page === "wallpaper") {
            run(["wallpaper-status"]);
            run(["wallpaper-list"]);
        } else if (page === "clipboard")
            run(["clipboard-list"]);
        else if (page === "windows")
            run(["windows-list"]);
    }
    function receive(action, result) {
        if (!result.ok) {
            error = result.error?.message || result.error || "Action failed";
            if (action.startsWith("brightness-")) {
                brightnessAvailable = false;
                brightnessError = error;
            }
            if (!action.endsWith("-status"))
                feedback(error, -1);
            return;
        }
        if (action.startsWith("brightness-")) {
            brightnessAvailable = result.available !== false;
            brightnessError = brightnessAvailable ? "" : (result.error?.message || result.error || "Display brightness is unavailable");
            brightness = result.percent || 0;
            if (action !== "brightness-status")
                feedback("Brightness", brightness / 100);
        } else if (action === "wallpaper-list")
            wallpapers = result.wallpapers || [];
        else if (action === "wallpaper-status" || action === "wallpaper-set") {
            wallpaper = result.path || "";
            if (action === "wallpaper-set")
                feedback("Wallpaper updated", -1);
        } else if (action === "clipboard-list")
            clipboard = result.items || [];
        else if (action === "clipboard-delete" || action === "clipboard-clear")
            run(["clipboard-list"]);
        else if (action === "clipboard-copy")
            feedback("Copied", -1);
        else if (action === "windows-list")
            windows = result.windows || [];
        else if (action.startsWith("nightlight-"))
            nightlight = result.enabled;
        else if (action.startsWith("power-")) {
            powerProfile = result.profile || "";
            powerProfiles = result.profiles || [];
        }
    }
    Process {
        id: worker
        property string action: ""
        stdout: StdioCollector {
            id: output
        }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            try {
                desktop.receive(action, JSON.parse(output.text));
            } catch (e) {
                desktop.error = "Desktop action failed: " + action;
                desktop.feedback(desktop.error, -1);
            }
            Qt.callLater(desktop.pump);
        }
    }
}
