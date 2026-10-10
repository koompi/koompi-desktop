import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarRight.volumeMixer
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: Appearance.spacing.small

    VolumeDialogContent {
        Layout.fillWidth: true
        Layout.fillHeight: true
        isSink: true
    }

    CcLinkRow {
        buttonText: Translation.tr("More sound settings")
        page: "sound"
    }
}
