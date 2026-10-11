import qs.modules.common
import QtQuick

Item {
    default property alias content: holder.data

    Item {
        id: holder
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
    }
}
