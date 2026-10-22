import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
        // an inline component cannot see root: the window carries the scheme
        color: QsWindow.window?.barScheme?.separator ?? Appearance.colors.colOutlineVariant
    }

    // Glass, after the macOS menu bar. Over the wallpaper the bar is blurred glass with a flat
    // tint (Hyprland blurs the quickshell:bar layer from 0.2 alpha), keeping the hug shape and
    // its corners. The tint is as light as legibility allows: the bar measures the wallpaper
    // under it (BarTone) and takes the least tint that keeps its text at 4.5:1. When glass of
    // the other tone needs clearly less - a bright wallpaper in dark mode - the text turns dark
    // over light glass (BarScheme.flipped). It goes solid when a window is under it, when the
    // wallpaper cannot be read, and with no Hyprland data (a nested test instance, the state
    // test_bar_contrast.sh measures).
    readonly property real glassFloor: 0.3
    // the geometry from the daemon's monitor; the workspace from Quickshell's, which follows a
    // switch at once where the daemon's monitor list can lag one
    readonly property var monitorData: HyprlandData.monitors.find(mon => mon.name === root.screen?.name) ?? null
    readonly property int workspaceId: Hyprland.monitorFor(root.screen)?.activeWorkspace?.id ?? 0
    readonly property string wallpaper: root.monitorData ? Wallpapers.forWorkspace(root.workspaceId) : ""
    onWallpaperChanged: BarTone.measure(root.wallpaper)
    Component.onCompleted: BarTone.measure(root.wallpaper)
    readonly property bool windowUnderBar: {
        const mon = root.monitorData;
        if (!mon)
            return true;
        const shown = [root.workspaceId, mon.specialWorkspace?.id].filter(id => id !== undefined && id !== 0);
        const height = mon.height / (mon.scale || 1);
        const bar = Appearance.sizes.barHeight;
        return HyprlandData.windowList.some(win => {
            if (!shown.includes(win.workspace?.id) || win.hidden || win.mapped === false)
                return false;
            const top = (win.at?.[1] ?? 0) - mon.y;
            const bottom = top + (win.size?.[1] ?? 0);
            return Config.options.bar.bottom ? bottom > height - bar : top < bar;
        });
    }
    BarScheme {
        id: themeProbe
    }
    BarScheme {
        id: flippedProbe
        flipped: true
    }
    readonly property var glassChoice: {
        const columns = BarTone.tones[root.wallpaper];
        if (!columns || root.windowUnderBar || !Config.options.bar.showBackground || !Config.options.bar.smartTransparency)
            return null;
        const own = themeProbe.tintOver(columns, root.glassFloor);
        const other = flippedProbe.tintOver(columns, root.glassFloor);
        const flip = other + 0.2 <= own;
        const tint = flip ? other : own;
        return tint < Appearance.colors.colBarBackground.a ? {
            "flipped": flip,
            "tint": tint
        } : null;
    }
    readonly property bool glass: root.glassChoice !== null
    readonly property BarScheme scheme: BarScheme {
        flipped: root.glassChoice?.flipped ?? false
    }
    // the bar's surface, shared with the hug corners so the two stay one shape
    readonly property color surfaceColor: !Config.options.bar.showBackground ? "transparent"
        : root.glass ? ColorUtils.applyAlpha(root.scheme.glass, root.glassChoice.tint) : Appearance.colors.colBarBackground

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
        color: root.surfaceColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
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
                colBackground: barLeftSideMouseArea.hovered ? root.scheme.element : ColorUtils.transparentize(root.scheme.fg, 0.965)
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
        // Hover and wheel only. The clock, the bell and the sliders glyph own their clicks; a
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
                color: root.scheme.fg
            }

            NetworkIndicator {
                Layout.alignment: Qt.AlignVCenter
            }

            BatteryIndicator {
                visible: (root.useShortenedForm < 2 && Battery.available)
                Layout.alignment: Qt.AlignVCenter
            }

            BarPanelButton { // quick settings
                id: controlCenterButton
                objectName: "controlCenterButton"
                colBackground: root.scheme.element
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

            NotificationButton {} // the bell, with the unread dot: opens the same panel

            BarPanelButton { // clock: opens the same panel
                objectName: "clockButton"
                Layout.rightMargin: Appearance.rounding.screenRounding - Appearance.spacing.small
                toggled: GlobalStates.sidebarRightOpen
                onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

                contentItem: Item {
                    implicitWidth: clockSlot.implicitWidth
                    implicitHeight: clockSlot.implicitHeight

                    PluginSlot { // time, far-right corner; date removed by default
                        id: clockSlot
                        anchors.centerIn: parent
                        pluginId: "koompi.clock"
                        builtin: ClockWidget {
                            showDate: false
                            color: GlobalStates.sidebarRightOpen ? Appearance.m3colors.m3onSecondaryContainer : root.scheme.fg
                        }
                    }
                }
            }
        }
    }
}
