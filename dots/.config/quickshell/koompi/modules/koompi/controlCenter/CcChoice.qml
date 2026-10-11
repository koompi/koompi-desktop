import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string title
    property bool current: false

    signal picked

    Layout.fillWidth: true
    implicitHeight: 38
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: root.title
    Accessible.checked: root.current

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.picked();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: area.containsMouse || root.activeFocus ? Appearance.colors.colLayer1Hover : "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: Appearance.spacing.normal
            rightMargin: Appearance.spacing.normal
        }
        spacing: Appearance.spacing.normal

        MaterialSymbol {
            iconSize: 20
            color: Appearance.colors.colPrimary
            text: root.current ? "radio_button_checked" : "radio_button_unchecked"
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.current ? Font.DemiBold : Font.Normal
            color: Appearance.colors.colOnLayer1
            text: root.title
        }
    }
}
