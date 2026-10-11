import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

BarButton {
    id: root

    required property string iconName
    property bool multiple: false
    property bool separateLightDark: false
    property bool plated: false
    property string label: ""
    leftInset: 2
    rightInset: 2
    implicitWidth: height - topInset - bottomInset + leftInset + rightInset

    property real pressedScale: 5/6

    onDownChanged: {
        scaleAnim.duration = root.down ? 150 : 200
        scaleAnim.easing.bezierCurve = root.down ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
        contentItem.scale = root.down ? root.pressedScale : 1 // If/When we do dragging, the scale is 1.25
    }

    background: Item {
        id: background
        BackgroundAcrylicRectangle {
            id: mainBgRect
            anchors.fill: parent
            layer.enabled: root.multiple
            layer.effect: OpacityMask {
                invert: true
                maskSource: Item {
                    width: mainBgRect.width
                    height: mainBgRect.height
                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 3
                        radius: mainBgRect.radius
                    }
                }
            }
        }
        Loader {
            anchors.fill: parent
            anchors.rightMargin: 5
            active: root.multiple
            sourceComponent: BackgroundAcrylicRectangle {}
        }
    }

    contentItem: Item {
        id: contentItem
        anchors.centerIn: root.background

        implicitHeight: root.plated ? appPlate.implicitHeight : iconWidget.implicitHeight
        implicitWidth: root.plated ? appPlate.implicitWidth : iconWidget.implicitWidth

        Behavior on scale {
            NumberAnimation {
                id: scaleAnim
                easing.type: Easing.BezierSpline
            }
        }

        WAppIcon {
            id: iconWidget
            visible: !root.plated
            anchors.centerIn: parent
            iconName: root.plated ? "" : root.iconName
            separateLightDark: root.separateLightDark
        }

        AppIconPlate {
            id: appPlate
            visible: root.plated
            anchors.centerIn: parent
            iconName: root.plated ? root.iconName : ""
            label: root.label
            size: 26
        }
    }

    component BackgroundAcrylicRectangle: AcrylicRectangle {
        shiny: ((root.hovered && !root.down) || root.checked)
        color: root.color
        border.width: 1
        border.color: root.colBackgroundBorder

        Behavior on border.color {
            animation: Looks.transition.color.createObject(this)
        }
    }
}
