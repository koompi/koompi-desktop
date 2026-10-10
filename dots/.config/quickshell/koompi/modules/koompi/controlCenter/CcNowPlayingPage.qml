import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.mediaControls
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: Appearance.spacing.small

    Loader {
        Layout.fillWidth: true
        active: MprisController.hasActiveMedia
        visible: active
        sourceComponent: PlayerControl {
            player: MprisController.activePlayer
            visualizerPoints: Cava.points
            implicitHeight: Appearance.sizes.mediaControlsHeight
            radius: Appearance.rounding.normal
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !MprisController.hasActiveMedia
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        text: Translation.tr("Nothing playing")
    }

    Item {
        Layout.fillHeight: true
    }
}
