import qs.modules.common
import QtQuick

Item {
    id: root

    property bool checked: false
    property string label
    // arrows walk the rows; the switch is reached by Tab
    readonly property bool tabOnly: true

    signal flipped

    implicitWidth: 40
    implicitHeight: 24
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.label
    Accessible.checked: root.checked

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.flipped();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colOnLayer1

        Rectangle {
            width: parent.height - 8
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 4 : 4
            color: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext

            Behavior on x {
                enabled: !Appearance.reduceMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        anchors {
            fill: parent
            margins: -4
        }
        cursorShape: Qt.PointingHandCursor
        onClicked: root.flipped()
    }
}
