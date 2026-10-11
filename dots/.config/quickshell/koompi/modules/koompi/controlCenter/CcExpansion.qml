import qs.modules.common
import QtQuick
import QtQuick.Layouts

// the drop-down under a row: folded it takes no room, and its page is not built
Rectangle {
    id: root

    property bool open: false
    property alias sourceComponent: body.sourceComponent
    // a negative height asks the page how tall it wants to be
    property real bodyHeight: -1
    readonly property real wanted: root.bodyHeight >= 0 ? root.bodyHeight : (body.item?.implicitHeight ?? 0)
    readonly property real pad: Appearance.spacing.small

    Layout.fillWidth: true
    Layout.preferredHeight: root.open ? root.wanted + root.pad * 2 : 0
    visible: Layout.preferredHeight > 0
    clip: true
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    Behavior on Layout.preferredHeight {
        enabled: !Appearance.reduceMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    Loader {
        id: body
        anchors {
            fill: parent
            margins: root.pad
        }
        active: root.visible
    }
}
