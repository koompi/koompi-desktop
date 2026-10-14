import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property color color: root.barScheme.fg
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.large
            color: root.color
            text: DateTime.time
        }

        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.color
            text: "•"
        }

        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.color
            text: DateTime.longDate
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.NoButton

        ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
