import QtQuick
import QtQuick.Effects
import "app-icon-plate.js" as Plate

// Shadow, fill and edge of one plate. Drawn live only until its texture is cached.
Item {
    id: root

    required property real side
    required property real margin
    required property color fill
    required property color edge
    required property color shadow
    property bool grab: false

    signal rendered(var result)

    width: root.side + root.margin * 2
    height: root.width

    RectangularShadow {
        x: root.margin
        y: root.margin
        width: root.side
        height: root.side
        radius: root.side * Plate.radiusRatio()
        blur: Math.min(Math.max(root.side * 0.09, 4), 10)
        offset: Qt.vector2d(0, Math.max(1, root.side * 0.02))
        color: root.shadow
    }

    Squircle {
        x: root.margin
        y: root.margin
        side: root.side
        inset: 0.5
        fill: root.fill
        stroke: root.edge
        strokeSize: 1
    }

    Timer {
        interval: 60
        running: root.grab
        onTriggered: root.grabToImage(result => root.rendered(result), Qt.size(root.width * 2, root.height * 2))
    }
}
