import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property string cardIcon
    property string cardTitle
    property bool interactive: true
    default property alias body: bodyColumn.data

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Appearance.spacing.normal * 2
    horizontalPadding: Appearance.spacing.normal
    buttonRadius: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: interactive ? Appearance.colors.colLayer1Hover : colBackground
    pointingHandCursor: interactive
    activeFocusOnTab: interactive

    contentItem: ColumnLayout {
        id: content
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small
            MaterialSymbol {
                iconSize: 18
                color: Appearance.colors.colPrimary
                text: root.cardIcon
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.cardTitle
            }
            MaterialSymbol {
                visible: root.interactive
                iconSize: 18
                color: Appearance.colors.colSubtext
                text: "chevron_right"
            }
        }
        ColumnLayout {
            id: bodyColumn
            Layout.fillWidth: true
            spacing: 2
        }
    }
}
