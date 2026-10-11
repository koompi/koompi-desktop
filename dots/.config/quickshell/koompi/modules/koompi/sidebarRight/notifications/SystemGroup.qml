import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Notices from the machine itself, folded by summary: six identical rows are one row reading ×6.
Rectangle {
    id: root
    objectName: "nc-system"
    property bool expanded: false
    readonly property var rows: Notifications.systemRows

    function clearAll() {
        root.rows.forEach(row => row.ids.forEach(id => Notifications.discardNotification(id)));
    }

    visible: rows.length > 0
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Appearance.spacing.normal * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: activeFocus ? 2 : 0
    border.color: Appearance.colors.colPrimary
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.expanded = !root.expanded;
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.clearAll();
            event.accepted = true;
        }
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Appearance.spacing.normal
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small
            MaterialSymbol {
                iconSize: 18
                color: Appearance.colors.colSubtext
                text: "settings_suggest"
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: Translation.tr("System")
            }
            SmallButton {
                glyph: "close"
                tip: Translation.tr("Clear these")
                onClicked: root.clearAll()
            }
            SmallButton {
                glyph: "keyboard_arrow_down"
                tip: root.expanded ? Translation.tr("Show less") : Translation.tr("Show all")
                rotation: root.expanded ? 180 : 0
                onClicked: root.expanded = !root.expanded
            }
        }

        Repeater {
            model: root.expanded ? root.rows : root.rows.slice(0, 1)
            delegate: RowLayout {
                id: sysRow
                required property var modelData
                required property int index
                readonly property string label: modelData.summary + (modelData.count > 1 ? " ×" + modelData.count : "")
                objectName: "nc-sysrow-" + index
                Layout.fillWidth: true
                spacing: Appearance.spacing.normal

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        text: sysRow.label
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        elide: Text.ElideRight
                        maximumLineCount: root.expanded ? 3 : 1
                        wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: sysRow.modelData.body
                    }
                }
                SmallButton { // a file: copy where it is
                    id: copyButton
                    objectName: "nc-syscopy-" + sysRow.index
                    property bool copied: false
                    visible: sysRow.modelData.path !== ""
                    glyph: copied ? "check" : "content_copy"
                    tip: Translation.tr("Copy path")
                    onClicked: {
                        Quickshell.clipboardText = sysRow.modelData.path;
                        copyButton.copied = true;
                        copiedTimer.restart();
                    }
                    Timer {
                        id: copiedTimer
                        interval: 1500
                        onTriggered: copyButton.copied = false
                    }
                }
                SmallButton { // a file: show it, selected, in the file manager
                    objectName: "nc-sysfolder-" + sysRow.index
                    visible: sysRow.modelData.path !== ""
                    glyph: "folder_open"
                    tip: Translation.tr("Show in folder")
                    onClicked: {
                        Notifications.showInFolder(sysRow.modelData.path);
                        GlobalStates.sidebarRightOpen = false;
                    }
                }
                SmallButton {
                    visible: root.expanded
                    glyph: "close"
                    tip: Translation.tr("Clear")
                    onClicked: sysRow.modelData.ids.forEach(id => Notifications.discardNotification(id))
                }
            }
        }
    }

    component SmallButton: RippleButton {
        property string glyph
        property string tip
        implicitWidth: 30
        implicitHeight: 24
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer2
            text: parent.glyph
        }
        StyledToolTip {
            text: parent.tip
        }
    }
}
