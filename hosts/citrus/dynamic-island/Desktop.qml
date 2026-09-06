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
    readonly property bool busy: worker.running || lockWorker.running || queue.length > 0
    signal feedback(string message, real value)

    function run(args) {
        if (testing && !Quickshell.env("ISLAND_TEST_ACTION"))
            return;
        error = "";
        if (args[0] === "lock") {
            runLock();
            return;
        }
        queue = queue.concat([args.map(String)]);
        pump();
    }
    function runLock() {
        if (lockWorker.running)
            return;
        lockWorker.command = [testing ? Quickshell.env("ISLAND_TEST_ACTION") : (Quickshell.env("ISLAND_ACTION") || "island-action"), "lock"];
        lockWorker.running = true;
    }
    function coalesceBrightness(result) {
        let target = result.percent;
        let position = -1;
        const remaining = [];
        // Fold keys and slider moves in order, including reversals at 0/100%.
        // Only the latest target needs another slow monitor transaction.
        for (const args of queue) {
            if (!args[0].startsWith("brightness-")) {
                remaining.push(args);
                continue;
            }
            if (position < 0)
                position = remaining.length;
            if (args[0] === "brightness-up")
                target = Math.min(100, target + 5);
            else if (args[0] === "brightness-down")
                target = Math.max(0, target - 5);
            else if (args[0] === "brightness-set")
                target = Number(args[1]);
        }
        if (result.ok && result.available !== false && position >= 0 && target !== result.percent) {
            const args = ["brightness-set", String(target)];
            if (result.backend === "ddc" && result.bus !== undefined)
                args.push("--bus", String(result.bus));
            remaining.splice(position, 0, args);
        }
        // Failed hardware requests also discard stale repeats, so recovery is immediate.
        queue = remaining;
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
        onExited: {
            try {
                const result = JSON.parse(output.text);
                desktop.receive(action, result);
                if (action.startsWith("brightness-"))
                    desktop.coalesceBrightness(result);
            } catch (e) {
                if (action.startsWith("brightness-"))
                    desktop.coalesceBrightness({
                        ok: false
                    });
                desktop.error = "Desktop action failed: " + action;
                desktop.feedback(desktop.error, -1);
            }
            Qt.callLater(desktop.pump);
        }
    }
    Process {
        id: lockWorker
        stdout: StdioCollector {
            id: lockOutput
        }
        stderr: StdioCollector {
            id: lockError
        }
        onExited: code => {
            try {
                const result = JSON.parse(lockOutput.text);
                if (code !== 0 || !result.ok) {
                    desktop.error = result.error?.message || result.error || "Desktop action failed: lock";
                    desktop.feedback(desktop.error, -1);
                }
            } catch (e) {
                desktop.error = lockError.text.trim() || "Desktop action failed: lock";
                desktop.feedback(desktop.error, -1);
            }
        }
    }
}
