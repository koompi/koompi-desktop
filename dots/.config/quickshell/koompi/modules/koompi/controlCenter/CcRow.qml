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
    // a row with choices: a click opens its list, and the on/off is the switch at its right end
    property bool expandable: false
    property bool expanded: false
    property bool hasSwitch: false
    // a grid tile: a filled card when on, and the icon disc is the switch of a row with choices
    property bool tile: false
    readonly property color colText: root.tile && root.toggled && root.hasToggle ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    readonly property color colSub: root.tile && root.toggled && root.hasToggle ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
    property string onWord: Translation.tr("On")
    property string offWord: Translation.tr("Off")
    property bool activateOpens: !hasToggle || expandable
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
    implicitHeight: root.tile ? CcMetrics.tileHeight : CcMetrics.rowHeight
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.5

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activate();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right && !root.tile && (root.hasDetail || root.expandable)) {
            root.opened();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.tile && root.toggled && root.hasToggle ? (area.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer) : area.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
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
        spacing: root.tile ? Appearance.spacing.small : Appearance.spacing.normal

        Rectangle {
            id: plate
            objectName: root.hasSwitch && root.tile ? root.objectName + "-switch" : ""
            readonly property bool tabOnly: true
            activeFocusOnTab: root.hasSwitch && root.tile
            Accessible.role: Accessible.CheckBox
            Accessible.name: root.title
            Accessible.checked: root.toggled
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.activated();
                    event.accepted = true;
                }
            }
            border.width: activeFocus ? 2 : 0
            border.color: Appearance.colors.colOnLayer1
            Layout.preferredWidth: CcMetrics.plate
            Layout.preferredHeight: CcMetrics.plate
            radius: root.toggled && root.hasToggle ? Appearance.rounding.small : width / 2
            color: root.toggled && root.hasToggle ? Appearance.colors.colPrimary : Appearance.colors.colLayer3

            MouseArea {
                anchors.fill: parent
                enabled: root.hasSwitch && root.tile
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated()
            }

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
                color: root.colText
                text: root.title
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colSub
                text: root.detail.length > 0 || !root.tile ? root.detail : root.stateWord
            }
        }

        RowLayout {
            id: trailingRow
            spacing: Appearance.spacing.small
        }

        StyledText {
            objectName: "state"
            visible: root.hasToggle && !root.hasSwitch && !root.tile
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.toggled ? Font.Bold : Font.Normal
            color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            text: root.stateWord
        }

        CcSwitch {
            objectName: root.objectName + "-switch"
            visible: root.hasSwitch && !root.tile
            checked: root.toggled
            label: root.title
            onFlipped: root.activated()
        }

        MaterialSymbol {
            visible: root.hasDetail || root.expandable
            iconSize: 20
            color: root.colSub
            text: root.expandable ? (root.expanded ? "expand_less" : "expand_more") : "chevron_right"

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
