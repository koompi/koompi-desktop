import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root

    property string glyph
    property string label

    implicitWidth: 34
    implicitHeight: 34
    buttonRadius: width / 2
    Accessible.name: root.label

    Rectangle {
        anchors.fill: parent
        radius: root.buttonRadius
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        iconSize: 22
        color: Appearance.colors.colOnLayer1
        text: root.glyph
    }
}
