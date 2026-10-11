import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

DialogButton {
    id: root

    property string page

    Layout.alignment: Qt.AlignRight
    onClicked: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/koompi-settings", root.page])
}
