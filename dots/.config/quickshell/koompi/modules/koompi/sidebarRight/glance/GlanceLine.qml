import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    property string lead
    property string text
    property bool muted: false

    Layout.fillWidth: true
    spacing: Appearance.spacing.normal

    StyledText {
        visible: root.lead.length > 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colPrimary
        text: root.lead
    }
    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
        text: root.text
    }
}
