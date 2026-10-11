import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Bar content region
    id: root

    readonly property bool menuOpen: activeWindow.menuOpen
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
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
        color: Config.options.bar.showBackground ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea
        // Clicks belong to the dedicated sidebar button and the global-menu
        // controls below. This parent exists only for hover and wheel input.
        acceptedButtons: Qt.NoButton

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleSection.left
        }
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        // Visual content
        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: leftSectionRowLayout
            anchors.fill: parent
            spacing: 0

            LeftSidebarButton { // Left sidebar button
                id: leftSidebarButton
                Layout.alignment: Qt.AlignVCenter
                // Same visual gap as the clock has on the right. The clock is
                // bare text, so screenRounding lands on its glyphs; the star is
                // centred in a button, so its box has to start that much sooner.
                Layout.leftMargin: Appearance.rounding.screenRounding - leftSidebarButton.iconInset
                // Resting veil, not transparent: the star's blades are separated
                // by hairline gaps that vanish against the bar without a field
                // behind them. Thinner than colBarElementBackground - this one
                // only has to separate the star, not carry a label.
                colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colBarElementBackground : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.965)
            }

            ActiveWindow {
                id: activeWindow
                Layout.leftMargin: Appearance.spacing.normal + (leftSidebarButton.visible ? 0 : Appearance.rounding.screenRounding)
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.useShortenedForm === 0
            }
        }
    }

    Row { // Middle section
        id: middleSection
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: Appearance.spacing.small

        BarGroup {
            id: middleCenterGroup
            anchors.verticalCenter: parent.verticalCenter
            padding: workspacesWidget.widgetPadding

            Workspaces {
                id: workspacesWidget
                Layout.fillHeight: true
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

                WorkspaceHelp {
                    target: workspacesWidget
                }
            }
        }

    }

    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea
        // Hover and wheel only. The clock and the sliders glyph own their clicks; a
        // strip-wide toggle would open the panel, which marks every notification read.
        acceptedButtons: Qt.NoButton

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleSection.right
            right: parent.right
        }
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;

        // Visual content
        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            spacing: Appearance.spacing.normal

            Item { // absorbs slack so the cluster pins to the right edge
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            SysTray {
                visible: root.useShortenedForm === 0
                Layout.fillWidth: false
                Layout.fillHeight: true
                invertSide: Config?.options.bar.bottom
            }

            BarGroup { // Media, only while something plays
                Layout.alignment: Qt.AlignVCenter
                visible: root.useShortenedForm === 0 && MprisController.hasActiveMedia

                Media {
                    Layout.fillHeight: true
                }
            }

            BarGroup { // AI-agent token usage
                Layout.alignment: Qt.AlignVCenter
                visible: root.useShortenedForm === 0 && AgentUsage.available

                AgentUsageIndicator {
                    Layout.fillHeight: true
                }
            }

            BarGroup { // Pomodoro, only while a lap is under way. Living in the
                // centered middle group pushed the workspaces off true center.
                id: pomodoroGroup
                Layout.alignment: Qt.AlignVCenter
                visible: root.useShortenedForm === 0 && pomodoro.inSession

                Pomodoro {
                    id: pomodoro
                    Layout.fillHeight: true
                }
            }

            ModeIndicators { // each only while on, each its own hit area
                Layout.alignment: Qt.AlignVCenter
            }

            UpdateBadge {}

            HyprlandXkbIndicator {
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnLayer0
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: Network.materialSymbol
                fill: Network.connected ? 1 : 0
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
                MouseArea {
                    id: networkHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
                PopupToolTip {
                    extraVisibleCondition: networkHover.containsMouse
                    anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
                    text: Network.networkName !== "" ? Network.networkName : Translation.tr("Network")
                }
            }

            BatteryIndicator {
                visible: (root.useShortenedForm < 2 && Battery.available)
                Layout.alignment: Qt.AlignVCenter
            }

            BarPanelButton { // quick settings
                id: controlCenterButton
                objectName: "controlCenterButton"
                colBackground: Appearance.colors.colBarElementBackground
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

            BarPanelButton { // clock: opens the same panel
                objectName: "clockButton"
                Layout.rightMargin: Appearance.rounding.screenRounding - Appearance.spacing.small
                toggled: GlobalStates.sidebarRightOpen
                onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                // the dot is laid out beside the time, not over it: an anchored dot sat on "AM" in 12-hour time
                contentItem: Item {
                    implicitWidth: clockRow.implicitWidth
                    implicitHeight: clockRow.implicitHeight

                    RowLayout {
                        id: clockRow
                        anchors.centerIn: parent
                        spacing: 4

                        PluginSlot { // time, far-right corner; date removed by default
                            pluginId: "koompi.clock"
                            builtin: ClockWidget {
                                showDate: false
                                color: GlobalStates.sidebarRightOpen ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                            }
                        }

                        NotificationUnreadCount {
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
