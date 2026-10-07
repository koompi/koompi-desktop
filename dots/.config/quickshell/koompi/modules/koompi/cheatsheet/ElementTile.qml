import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    required property var element
    // text keeps its size down to this tile height, then shrinks with the tile
    readonly property real textScale: Math.max(0.7, Math.min(1, height / 56))
    opacity: element.type != "empty" ? 1 : 0
    implicitHeight: 70
    implicitWidth: 70
    colBackground: Appearance.colors.colLayer2
    buttonRadius: Appearance.rounding.small

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 4
            leftMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementNumber.implicitWidth)
        implicitHeight: Math.max(20, elementNumber.implicitHeight)
        width: height

        StyledText {
            id: elementNumber
            anchors.left: parent.left
            color: Appearance.colors.colOnLayer2
            text: root.element.number
            font.pixelSize: Math.round(Appearance.font.pixelSize.smallest * root.textScale)
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 4
            rightMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementWeight.implicitWidth)
        implicitHeight: Math.max(20, elementWeight.implicitHeight)
        width: height

        StyledText {
            id: elementWeight
            anchors.right: parent.right
            color: Appearance.colors.colOnLayer2
            text: root.element.weight
            font.pixelSize: Math.round(Appearance.font.pixelSize.smallest * root.textScale)
        }
    }

    StyledText {
        id: elementSymbol
        anchors.centerIn: parent
        color: Appearance.colors.colSecondary
        font.pixelSize: Math.round(Appearance.font.pixelSize.huge * root.textScale)
        text: root.element.symbol
    }

    StyledText {
        id: elementName
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 4
        }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        // the long names (Praseodymium, Rutherfordium) shrink to a narrower tile instead of leaving it
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 8
        font.pixelSize: Math.round(Appearance.font.pixelSize.smallest * root.textScale)
        color: Appearance.colors.colOnLayer2
        text: root.element.name
    }
}
