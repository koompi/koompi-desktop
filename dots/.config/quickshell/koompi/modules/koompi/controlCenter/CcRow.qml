import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string icon
    property string title
    property string detail
    property bool hasToggle: true
    property bool toggled: false
    property bool hasDetail: false
    property string onWord: Translation.tr("On")
    property string offWord: Translation.tr("Off")
    property bool activateOpens: !hasToggle
    readonly property string stateWord: !hasToggle ? "" : toggled ? onWord : offWord
    property alias trailing: trailingRow.data

    signal activated
    signal opened

    function activate(): void {
        if (activateOpens)
            root.opened();
        else
            root.activated();
    }

    Layout.fillWidth: true
    implicitHeight: CcMetrics.rowHeight
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.5

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activate();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right && root.hasDetail) {
            root.opened();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocusReason);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: area.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: Appearance.spacing.normal
            rightMargin: Appearance.spacing.normal
        }
        spacing: Appearance.spacing.normal

        Rectangle {
            Layout.preferredWidth: CcMetrics.plate
            Layout.preferredHeight: CcMetrics.plate
            radius: root.toggled && root.hasToggle ? Appearance.rounding.small : width / 2
            color: root.toggled && root.hasToggle ? Appearance.colors.colPrimary : Appearance.colors.colLayer3

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 22
                fill: root.toggled && root.hasToggle ? 1 : 0
                color: root.toggled && root.hasToggle ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                text: root.icon
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: root.title
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.detail
            }
        }

        RowLayout {
            id: trailingRow
            spacing: Appearance.spacing.small
        }

        StyledText {
            objectName: "state"
            visible: root.hasToggle
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.toggled ? Font.Bold : Font.Normal
            color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            text: root.stateWord
        }

        MaterialSymbol {
            visible: root.hasDetail
            iconSize: 20
            color: Appearance.colors.colSubtext
            text: "chevron_right"

            MouseArea {
                anchors {
                    fill: parent
                    margins: -8
                }
                cursorShape: Qt.PointingHandCursor
                onClicked: root.opened()
            }
        }
    }
}
