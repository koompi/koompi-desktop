import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.koompi.sidebarLeft.aiChat.composer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Which brain is answering and whether it can hear the network, in the one place
// the whole surface shares. A click opens the sidebar's model picker under it:
// the window's composer runs no /model, so this is the one way to switch here.
Rectangle {
    id: root

    readonly property var model: Ai.models ? Ai.models[Ai.currentModelId] : null
    readonly property string endpoint: root.model?.endpoint ?? ""
    readonly property bool local: root.endpoint.includes("127.0.0.1") || root.endpoint.includes("localhost")

    implicitWidth: chipRow.implicitWidth + Appearance.spacing.normal * 2
    implicitHeight: chipRow.implicitHeight + Appearance.spacing.small * 2
    radius: Appearance.rounding.full
    color: root.local ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        MaterialSymbol {
            text: root.local ? "home_pin" : "cloud"
            iconSize: Appearance.font.pixelSize.normal
            color: root.local ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
        }

        StyledText {
            text: (root.model?.model ?? "").length > 0 ? Ai.guessModelName(root.model.model) : Translation.tr("no model")
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.local ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
        }

        StyledText {
            text: root.local ? Translation.tr("local") : Translation.tr("cloud")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.local ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Switch model")

    MouseArea {
        id: chipHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pickerPopup.opened ? pickerPopup.close() : pickerPopup.open()
    }

    StyledToolTip {
        text: (root.endpoint.length > 0 ? root.endpoint : Translation.tr("no endpoint configured"))
            + "\n" + Translation.tr("Click to switch model")
        extraVisibleCondition: chipHover.containsMouse && !pickerPopup.opened
    }

    Popup {
        id: pickerPopup
        y: root.height + Appearance.spacing.small
        x: root.width - width
        width: 320
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: null
        onOpened: picker.focusFirst()

        ModelPicker {
            id: picker
            width: parent.width
            visible: pickerPopup.opened
            models: Ai.modelList.map(id => ({
                id: id,
                name: Ai.models[id]?.name ?? id,
                description: Ai.models[id]?.description ?? "",
                auth: Ai.models[id]?.auth ?? ""
            }))
            currentId: Ai.currentModelId
            onPicked: id => {
                pickerPopup.close();
                Ai.setModel(id);
            }
            onDismissed: pickerPopup.close()
            onProvidersRequested: {
                pickerPopup.close();
                SettingsPages.openNamed("ai");
            }
        }
    }
}
