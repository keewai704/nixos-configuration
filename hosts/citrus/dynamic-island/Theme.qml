import QtQuick
import Quickshell

QtObject {
    id: theme

    readonly property var values: {
        const raw = Quickshell.env("ISLAND_THEME") || "{}";
        try {
            const parsed = JSON.parse(raw);
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (error) {
            return {};
        }
    }

    function value(name, fallback) {
        const candidate = values[name];
        return typeof candidate === "string" && candidate.length > 0 ? candidate : fallback;
    }

    readonly property color background: "#000000"
    readonly property color surface: value("surface", "#292e42")
    readonly property color hover: value("hover", "#3b4261")
    readonly property color border: value("border", "#3b4261")
    readonly property color text: value("text", "#c0caf5")
    readonly property color muted: value("muted", "#a9b1d6")
    readonly property color accent: value("accent", "#7aa2f7")
    readonly property color onAccent: value("onAccent", "#1a1b26")
    readonly property string fontFamily: value("fontFamily", "sans-serif")
    readonly property real fontSize: Number(values.fontSize) > 0 ? Number(values.fontSize) : 13
}
