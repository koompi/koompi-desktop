import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: screenCorners
    property var actionForCorner: ({
        [RoundCorner.CornerEnum.TopLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
        [RoundCorner.CornerEnum.BottomLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
        [RoundCorner.CornerEnum.TopRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen,
        [RoundCorner.CornerEnum.BottomRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    })

    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        required property int corner
        property bool drawsRounding
        property bool hostsHotCorner

        readonly property bool isTop: corner === RoundCorner.CornerEnum.TopLeft || corner === RoundCorner.CornerEnum.TopRight
        readonly property bool isBottom: !isTop
        readonly property bool isLeft: corner === RoundCorner.CornerEnum.TopLeft || corner === RoundCorner.CornerEnum.BottomLeft
        readonly property bool isRight: !isLeft

        readonly property int roundingSize: drawsRounding ? Appearance.rounding.screenRounding : 0
        readonly property int regionWidth: hostsHotCorner ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
        readonly property int regionHeight: hostsHotCorner ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0

        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: cornerPanelWindow.hostsHotCorner ? hotCornerLoader : null
        }
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerPanelWindow.isTop
            left: cornerPanelWindow.isLeft
            bottom: cornerPanelWindow.isBottom
            right: cornerPanelWindow.isRight
        }
        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * -1
        }

        implicitWidth: Math.max(roundingSize, regionWidth)
        implicitHeight: Math.max(roundingSize, regionHeight)

        Loader {
            active: cornerPanelWindow.drawsRounding
            anchors.fill: parent
            sourceComponent: RoundCorner {
                corner: cornerPanelWindow.corner
                rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * 1
                bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * 1
                implicitSize: cornerPanelWindow.roundingSize
            }
        }

        Loader {
            id: hotCornerLoader
            active: cornerPanelWindow.hostsHotCorner
            anchors {
                top: cornerPanelWindow.isTop ? parent.top : undefined
                bottom: cornerPanelWindow.isBottom ? parent.bottom : undefined
                left: cornerPanelWindow.isLeft ? parent.left : undefined
                right: cornerPanelWindow.isRight ? parent.right : undefined
            }

            sourceComponent: FocusedScrollMouseArea {
                id: mouseArea
                implicitWidth: cornerPanelWindow.regionWidth
                implicitHeight: cornerPanelWindow.regionHeight
                hoverEnabled: true
                property bool armed: true
                onExited: armed = true
                onPositionChanged: {
                    if (!armed || !Config.options.sidebar.cornerOpen.clicklessCornerEnd) return;
                    const verticalOffset = Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset;
                    const correctX = (cornerPanelWindow.isRight && mouseArea.mouseX >= mouseArea.width - 2) || (cornerPanelWindow.isLeft && mouseArea.mouseX <= 2);
                    const correctY = (cornerPanelWindow.isTop && mouseArea.mouseY > verticalOffset || cornerPanelWindow.isBottom && mouseArea.mouseY < mouseArea.height - verticalOffset);
                    if (correctX && correctY) {
                        armed = false;
                        screenCorners.actionForCorner[cornerPanelWindow.corner]();
                    }
                }
                onEntered: {
                    if (Config.options.sidebar.cornerOpen.clickless)
                        screenCorners.actionForCorner[cornerPanelWindow.corner]();
                }
                onPressed: {
                    screenCorners.actionForCorner[cornerPanelWindow.corner]();
                }
                onScrollDown: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        Brightness.decreaseBrightness()
                    else {
                        const currentVolume = Audio.value;
                        const step = currentVolume < 0.1 ? 0.01 : 0.02;
                        Audio.sink.audio.volume -= step;
                    }
                }
                onScrollUp: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        Brightness.increaseBrightness()
                    else {
                        const currentVolume = Audio.value;
                        const step = currentVolume < 0.1 ? 0.01 : 0.02;
                        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
                    }
                }
                onMovedAway: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        GlobalStates.osdBrightnessOpen = false;
                    else
                        GlobalStates.osdVolumeOpen = false;
                }

                Loader {
                    active: Config.options.sidebar.cornerOpen.visualize
                    anchors.fill: parent
                    sourceComponent: Rectangle {
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // Hide when fullscreen
            property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            property bool fullscreen: activeWorkspaceWithFullscreen != undefined

            readonly property int fakeRounding: Config.options.appearance.fakeScreenRounding
            readonly property bool drawsRounding: fakeRounding === 1 || (fakeRounding === 2 && !fullscreen)
            readonly property bool hotCornersLive: Config.options.sidebar.cornerOpen.enable && !fullscreen

            Variants {
                model: [RoundCorner.CornerEnum.TopLeft, RoundCorner.CornerEnum.TopRight, RoundCorner.CornerEnum.BottomLeft, RoundCorner.CornerEnum.BottomRight]

                LazyLoader {
                    id: cornerLoader
                    required property int modelData
                    readonly property bool isBottom: modelData === RoundCorner.CornerEnum.BottomLeft || modelData === RoundCorner.CornerEnum.BottomRight
                    readonly property bool hostsHotCorner: monitorScope.hotCornersLive && Config.options.sidebar.cornerOpen.bottom === isBottom
                    active: monitorScope.drawsRounding || hostsHotCorner

                    component: CornerPanelWindow {
                        screen: monitorScope.modelData
                        corner: cornerLoader.modelData
                        drawsRounding: monitorScope.drawsRounding
                        hostsHotCorner: cornerLoader.hostsHotCorner
                    }
                }
            }
        }
    }
}
