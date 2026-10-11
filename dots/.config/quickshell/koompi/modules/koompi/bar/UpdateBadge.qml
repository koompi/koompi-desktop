import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// its own item beside the status cluster: a click meant for a panel glyph must not reach updates
Revealer {
    id: root

    readonly property var tooltipEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top

    reveal: Updates.available && Updates.count > 0
    Layout.alignment: Qt.AlignVCenter

    onRevealChanged: {
        if (!reveal) popup.close();
    }

    RippleButton {
        id: button
        objectName: "updateBadge"

        implicitWidth: Appearance.font.pixelSize.larger + Appearance.spacing.small * 2
        implicitHeight: implicitWidth
        padding: 0
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive
        toggled: popup.active
        middleClickAction: () => Updates.refresh()

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "system_update"
            iconSize: Appearance.font.pixelSize.larger
            color: button.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
        }

        PopupToolTip {
            extraVisibleCondition: !popup.active
            anchorEdges: root.tooltipEdges
            text: Translation.tr("Updates available")
        }
    }

    UpdatesPopup {
        id: popup
        objectName: "updatesPopup"
        hoverTarget: button
    }
}
