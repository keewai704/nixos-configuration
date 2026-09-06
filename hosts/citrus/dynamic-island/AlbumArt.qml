pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

ClippingRectangle {
    id: artwork
    property url source
    property int duration: 200
    property real pixelRatio: 1
    property bool firstActive: true
    property bool complete: false
    readonly property bool available: !!source.toString() && (firstActive ? first.status : second.status) === Image.Ready
    radius: 14

    function load() {
        const next = firstActive ? second : first;
        next.source = source;
        if (next.status !== Image.Loading)
            firstActive = next === first;
    }
    onSourceChanged: if (complete)
        load()
    Component.onCompleted: {
        complete = true;
        load();
    }

    component Cover: Image {
        id: cover
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.ceil(width * artwork.pixelRatio), Math.ceil(height * artwork.pixelRatio))
        asynchronous: true
        onStatusChanged: {
            if (source === artwork.source && status !== Image.Loading)
                artwork.firstActive = cover === first;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: artwork.duration
            }
        }
    }
    Cover {
        id: first
        opacity: artwork.firstActive ? 1 : 0
    }
    Cover {
        id: second
        opacity: artwork.firstActive ? 0 : 1
    }
}
