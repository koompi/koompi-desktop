import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One provider in Settings > AI: its mark, its name, one line of state, and the
 * actions on the right. `logo` is an icon in assets/icons, else `icon` a symbol.
 */
ColumnLayout {
    id: root

    property string icon: ""
    property string logo: ""
    property string title: ""
    property string subtitle: ""
    property bool subtitleIsProblem: false
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Item {
            implicitWidth: 24
            implicitHeight: 24
            Layout.alignment: Qt.AlignVCenter
            CustomIcon {
                visible: root.logo.length > 0
                anchors.fill: parent
                source: root.logo
                colorize: true
                color: Appearance.colors.colOnLayer1
            }
            MaterialSymbol {
                visible: root.logo.length === 0
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.title
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.subtitleIsProblem ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: root.subtitle
            }
        }

        RowLayout {
            id: actionRow
            spacing: 4
        }
    }
}
