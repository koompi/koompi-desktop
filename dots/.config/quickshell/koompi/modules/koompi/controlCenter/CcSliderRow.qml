import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string icon
    property string title
    property string detail
    property real value: 0
    property bool hasDetail: false
    property bool expandable: false
    property bool expanded: false

    signal moved(real value)
    signal opened

    function step(delta: real): void {
        root.moved(Math.max(0, Math.min(1, root.value + delta)));
    }

    Layout.fillWidth: true
    implicitHeight: CcMetrics.sliderHeight
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            root.step(event.key === Qt.Key_Left ? -0.05 : 0.05);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && root.hasDetail) {
            root.opened();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: Appearance.spacing.normal
            rightMargin: Appearance.spacing.normal
            topMargin: Appearance.spacing.small
            bottomMargin: Appearance.spacing.small
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            Rectangle {
                Layout.preferredWidth: CcMetrics.plate
                Layout.preferredHeight: CcMetrics.plate
                radius: width / 2
                color: Appearance.colors.colLayer3
                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                    text: root.icon
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    text: root.title
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.detail
                }
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: `${Math.round(root.value * 100)}%`
            }

            MaterialSymbol {
                visible: root.hasDetail
                iconSize: 20
                color: Appearance.colors.colSubtext
                text: root.expandable ? (root.expanded ? "expand_less" : "expand_more") : "chevron_right"
                MouseArea {
                    anchors {
                        fill: parent
                        margins: -8
                    }
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.opened()
                }
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.S
            stopIndicatorValues: []
            focusPolicy: Qt.NoFocus
            value: root.value
            onMoved: root.moved(value)
        }
    }
}
