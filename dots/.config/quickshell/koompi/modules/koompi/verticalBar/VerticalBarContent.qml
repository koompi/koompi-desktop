import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.koompi.bar as Bar

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    component HorizontalBarSeparator: Rectangle {
        Layout.leftMargin: Appearance.sizes.baseBarHeight / 3
        Layout.rightMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    FocusedScrollMouseArea { // Top section | scroll to change brightness
        id: barTopSectionMouseArea
        // Clicks belong to the left sidebar button below, as in the
        // horizontal bar. This parent exists only for hover and wheel input.
        acceptedButtons: Qt.NoButton
        anchors.top: parent.top
        implicitHeight: topSectionColumnLayout.implicitHeight
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        height: (root.height - middleSection.height) / 2
        width: Appearance.sizes.verticalBarWidth

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false

        ColumnLayout { // Content
            id: topSectionColumnLayout
            anchors.fill: parent
            spacing: 10

            Bar.LeftSidebarButton { // Left sidebar button
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: (Appearance.sizes.baseVerticalBarWidth - implicitWidth) / 2 + Appearance.sizes.hyprlandGapsOut
                colBackground: barTopSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
            }

            Item {
                Layout.fillHeight: true
            }
            
        }
    }

    Column { // Middle section
        id: middleSection
        anchors.centerIn: parent
        spacing: 4

        Bar.BarGroup {
            vertical: true
            padding: 8
            Resources {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            
            HorizontalBarSeparator {}

            VerticalMedia {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
        }

        HorizontalBarSeparator {
            visible: Config.options?.bar.borderless
        }

        Bar.BarGroup {
            id: middleCenterGroup
            vertical: true
            padding: 6

            Bar.Workspaces {
                id: workspacesWidget
                vertical: true
                MouseArea {
                    // Right-click to toggle overview
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton

                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                        }
                    }
                }

                Bar.WorkspaceHelp {
                    target: workspacesWidget
                }
            }
        }

        HorizontalBarSeparator {
            visible: Config.options?.bar.borderless
        }

        Bar.BarGroup {
            vertical: true
            padding: 8
            
            Bar.BarPanelButton { // clock: opens the same panel
                objectName: "clockButton"
                vertical: true
                Layout.fillWidth: true
                toggled: GlobalStates.sidebarRightOpen
                onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                contentItem: VerticalClockWidget {
                    color: GlobalStates.sidebarRightOpen ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                }
            }

            Bar.NotificationButton { // the bell, with the unread dot: opens the same panel
                vertical: true
                Layout.fillWidth: true
            }

            HorizontalBarSeparator {
                visible: Battery.available
            }

            BatteryIndicator {
                visible: Battery.available
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            
        }
    }

    FocusedScrollMouseArea { // Bottom section | scroll to change volume
        id: barBottomSectionMouseArea
        // Clicks belong to the sliders button below. This parent exists only for hover and wheel input.
        acceptedButtons: Qt.NoButton

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        implicitHeight: bottomSectionColumnLayout.implicitHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;

        ColumnLayout {
            id: bottomSectionColumnLayout
            anchors.fill: parent
            spacing: 4

            Item { 
                Layout.fillWidth: true
                Layout.fillHeight: true 
            }

            Bar.SysTray {
                vertical: true
                Layout.fillWidth: true
                Layout.fillHeight: false
                invertSide: Config?.options.bar.bottom
            }

            Bar.ModeIndicators {
                vertical: true
                realSpacing: 6
                Layout.alignment: Qt.AlignHCenter
            }

            Bar.HyprlandXkbIndicator {
                vertical: true
                Layout.alignment: Qt.AlignHCenter
                color: Appearance.colors.colOnLayer0
            }

            Bar.NetworkIndicator {
                Layout.alignment: Qt.AlignHCenter
            }

            Bar.BarPanelButton { // quick settings
                id: controlCenterButton
                objectName: "controlCenterButton"
                colBackground: Appearance.colors.colBarElementBackground
                vertical: true
                Layout.bottomMargin: Appearance.rounding.screenRounding
                toggled: GlobalStates.sidebarRightOpen
                tooltip: Translation.tr("Quick settings")
                onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "tune"
                    fill: GlobalStates.sidebarRightOpen ? 1 : 0
                    iconSize: Appearance.font.pixelSize.larger
                    color: controlCenterButton.colText
                }
            }
        }
    }
}
