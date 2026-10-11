import QtQuick
import QtQuick.Shapes
import "app-icon-plate.js" as Plate

Shape {
    id: root

    property real side: 48
    property real inset: 0
    property color fill: "transparent"
    property color stroke: "transparent"
    property real strokeSize: 0

    readonly property real r: root.side * Plate.radiusRatio() - root.inset
    readonly property real k: root.r * Plate.cornerHandle()
    readonly property real lo: root.inset
    readonly property real hi: root.side - root.inset

    implicitWidth: root.side
    implicitHeight: root.side
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.fill
        strokeColor: root.stroke
        strokeWidth: root.strokeSize
        startX: root.lo + root.r
        startY: root.lo
        PathLine { x: root.hi - root.r; y: root.lo }
        PathCubic {
            control1X: root.hi - root.r + root.k; control1Y: root.lo
            control2X: root.hi; control2Y: root.lo + root.r - root.k
            x: root.hi; y: root.lo + root.r
        }
        PathLine { x: root.hi; y: root.hi - root.r }
        PathCubic {
            control1X: root.hi; control1Y: root.hi - root.r + root.k
            control2X: root.hi - root.r + root.k; control2Y: root.hi
            x: root.hi - root.r; y: root.hi
        }
        PathLine { x: root.lo + root.r; y: root.hi }
        PathCubic {
            control1X: root.lo + root.r - root.k; control1Y: root.hi
            control2X: root.lo; control2Y: root.hi - root.r + root.k
            x: root.lo; y: root.hi - root.r
        }
        PathLine { x: root.lo; y: root.lo + root.r }
        PathCubic {
            control1X: root.lo; control1Y: root.lo + root.r - root.k
            control2X: root.lo + root.r - root.k; control2Y: root.lo
            x: root.lo + root.r; y: root.lo
        }
    }
}
