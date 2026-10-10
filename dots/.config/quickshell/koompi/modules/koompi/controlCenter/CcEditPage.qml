import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: Appearance.spacing.small

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("Shown modules appear under Sound. Wi-Fi, Bluetooth, Do Not Disturb, Keep awake, Display and Sound are always there.")
    }

    Repeater {
        model: CcExtras.types
        delegate: CcExtraRow {
            required property string modelData
            type: modelData
            editing: true
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
