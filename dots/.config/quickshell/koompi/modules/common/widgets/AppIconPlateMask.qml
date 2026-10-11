import QtQuick
import QtQuick.Effects

// A full-bleed icon cut to the squircle so its body fills the plate. Drawn live only until its texture is cached.
Item {
    id: root

    required property real side
    required property string source
    required property real lo
    required property real hi
    property bool grab: false

    signal rendered(var result)
    signal failed()

    readonly property real full: root.side / (root.hi - root.lo)

    width: root.side
    height: root.side

    Squircle {
        id: cutter
        side: root.side
        fill: "black"
        visible: false
        layer.enabled: true
    }

    Item {
        width: root.side
        height: root.side
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cutter
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Image {
            id: art
            x: -root.lo * root.full
            y: -root.lo * root.full
            width: root.full
            height: root.full
            sourceSize: Qt.size(root.full * 2, root.full * 2)
            source: root.source
            asynchronous: true
            smooth: true
            mipmap: true
            onStatusChanged: {
                if (art.status === Image.Error) root.failed();
                else if (art.status === Image.Ready && root.grab) grabTimer.restart();
            }
        }
    }

    Timer {
        id: grabTimer
        interval: 60
        onTriggered: root.grabToImage(result => root.rendered(result), Qt.size(root.side * 2, root.side * 2))
    }

    onGrabChanged: if (root.grab && art.status === Image.Ready) grabTimer.restart()
}
