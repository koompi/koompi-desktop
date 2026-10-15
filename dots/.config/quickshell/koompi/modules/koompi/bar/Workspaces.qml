import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "../../common/functions/workspace-slots.js" as Slots

Item {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1
    readonly property bool focusingThisMonitor: Hyprland.focusedMonitor?.id === root.monitor?.id
    
    // dynamic draws only the desks in use over Hyprland's group of ten; the
    // desk numbers never change either way
    readonly property bool dynamicSlots: Config.options.bar.workspaces.dynamic
    readonly property int workspacesShown: dynamicSlots ? 10 : Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / root.workspacesShown)
    readonly property int groupBase: workspaceGroup * root.workspacesShown
    property var occupiedIds: []
    readonly property var slotInfo: dynamicSlots
        ? Slots.slots(occupiedIds, effectiveActiveWorkspaceId, workspacesShown)
        : Slots.fixed(effectiveActiveWorkspaceId, workspacesShown)
    readonly property var slotIds: slotInfo.ids
    readonly property int newSlotId: slotInfo.newId
    property real drawnLength: slotIds.length * workspaceButtonWidth
    Behavior on drawnLength {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property int widgetPadding: 4
    // Pitch, and therefore the pointer target, of one workspace button. A bar
    // height wide so every button is a bar-height square to click; the pills
    // drawn inside stay `workspaceVisualSize` so the bar looks unchanged.
    property int workspaceButtonWidth: Appearance.sizes.baseBarHeight
    property int workspaceVisualSize: 26
    property real activeWorkspaceMargin: 2
    property real workspaceIconSize: workspaceVisualSize * 0.69
    property int workspaceIndexInGroup: Math.max(0, slotIds.indexOf(effectiveActiveWorkspaceId))

    property bool showNumbers: false
    Timer {
        id: showNumbersTimer
        // showNumberDelay, not autoHide.showWhenPressingSuper.delay: that one
        // paces revealing a hidden bar, and Settings offers this one under
        // "Number show delay when pressing Super". Reading the other left the
        // spinbox wired to nothing.
        interval: (Config?.options.bar.workspaces.showNumberDelay ?? 300)
        repeat: false
        onTriggered: {
            root.showNumbers = true
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
            if (GlobalStates.superDown) showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbers = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() { 
            showNumbersTimer.stop()
        }
    }

    function updateWorkspaceOccupied() {
        occupiedIds = Hyprland.workspaces.values.map(ws => ws.id);
    }

    function isSlot(id) {
        return slotIds.indexOf(id) >= 0;
    }

    function isOccupied(id) {
        return occupiedIds.indexOf(id) >= 0;
    }

    // a lit pill behind an occupied desk, except the active one while no window has focus
    function pillOn(i) {
        const id = groupBase + i + 1;
        return isSlot(id) && isOccupied(id) && !(!activeWindow?.activated && effectiveActiveWorkspaceId === id);
    }

    // the nearest drawn desk on one side decides whether a pill runs on into it
    function pillBeside(i, step) {
        for (let j = i + step; j >= 0 && j < workspacesShown; j += step) {
            if (isSlot(groupBase + j + 1)) return pillOn(j);
        }
        return false;
    }

    // each drawn desk's id, or "id:face" with withFaces
    function drawnIds(withFaces) {
        const out = [];
        for (let i = 0; i < numberButtons.count; i++) {
            const item = numberButtons.itemAt(i);
            if (item && item.shown) out.push(withFaces ? item.workspaceValue + ":" + item.background.face : item.workspaceValue);
        }
        return out;
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
        }
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.drawnLength
    implicitHeight: root.vertical ? root.drawnLength : Appearance.sizes.barHeight

    // Scroll to switch workspaces
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            } 
        }
    }

    // Workspaces - background
    Grid {
        z: 1
        anchors.left: root.vertical ? undefined : parent.left
        anchors.top: root.vertical ? parent.top : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

        rowSpacing: 0
        columnSpacing: 0
        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1

        Repeater {
            model: root.workspacesShown

            Rectangle {
                z: 1
                property real extent: root.isSlot(root.groupBase + index + 1) ? workspaceButtonWidth : 0
                Behavior on extent {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                implicitWidth: root.vertical ? root.workspaceVisualSize : extent
                implicitHeight: root.vertical ? extent : root.workspaceVisualSize
                radius: (root.workspaceVisualSize / 2)
                property bool previousOccupied: root.pillBeside(index, -1)
                property bool rightOccupied: root.pillBeside(index, 1)
                property real radiusPrev: previousOccupied ? 0 : (root.workspaceVisualSize / 2)
                property real radiusNext: rightOccupied ? 0 : (root.workspaceVisualSize / 2)

                topLeftRadius: radiusPrev
                bottomLeftRadius: root.vertical ? radiusNext : radiusPrev
                topRightRadius: root.vertical ? radiusPrev : radiusNext
                bottomRightRadius: radiusNext

                color: root.barScheme.element
                opacity: root.pillOn(index) ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusPrev {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Behavior on radiusNext {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
    }

    // Active workspace
    Rectangle {
        z: 2
        // Make active ws indicator, which has a brighter color, smaller to look like it is of the same size as ws occupied highlight
        radius: Appearance.rounding.full
        // Dimmed on a monitor that does not hold focus, so the focused one's
        // active workspace is the one that reads as active.
        color: root.focusingThisMonitor ? root.barScheme.elementActive : root.barScheme.element

        anchors {
            verticalCenter: vertical ? undefined : parent.verticalCenter
            horizontalCenter: vertical ? parent.horizontalCenter : undefined
        }

        AnimatedTabIndexPair {
            id: idxPair
            index: root.workspaceIndexInGroup
        }
        property real indicatorPosition: Math.min(idxPair.idx1, idxPair.idx2) * workspaceButtonWidth + root.activeWorkspaceMargin
        property real indicatorLength: Math.abs(idxPair.idx1 - idxPair.idx2) * workspaceButtonWidth + workspaceButtonWidth - root.activeWorkspaceMargin * 2
        property real indicatorThickness: root.workspaceVisualSize - root.activeWorkspaceMargin * 2

        x: root.vertical ? null : indicatorPosition
        implicitWidth: root.vertical ? indicatorThickness : indicatorLength
        y: root.vertical ? indicatorPosition : null
        implicitHeight: root.vertical ? indicatorLength : indicatorThickness

    }

    // Workspaces - numbers
    Grid {
        z: 3

        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1
        columnSpacing: 0
        rowSpacing: 0

        anchors.fill: parent

        Repeater {
            id: numberButtons
            model: root.workspacesShown

            Button {
                id: button
                objectName: "workspaceSlot" + workspaceValue
                property int workspaceValue: root.groupBase + index + 1
                readonly property bool shown: root.isSlot(workspaceValue)
                readonly property bool isNew: workspaceValue === root.newSlotId
                property real extent: shown ? root.workspaceButtonWidth : 0
                Behavior on extent {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                enabled: shown
                clip: true
                opacity: root.workspaceButtonWidth > 0 ? extent / root.workspaceButtonWidth : 0
                implicitHeight: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
                implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.verticalBarWidth
                onPressed: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceValue}})`)
                width: vertical ? undefined : extent
                height: vertical ? extent : undefined

                StyledToolTip {
                    extraVisibleCondition: button.isNew
                    text: Translation.tr("New desk")
                }

                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(button.workspaceValue)
                    property string mainAppIconName: AppSearch.guessIcon(biggestWindow?.class)
                    // the app on the desk, else its number; holding Super shows the numbers to type
                    readonly property string face: Slots.face(
                        root.showNumbers || !!Config.options?.bar.workspaces.alwaysShowNumbers,
                        !!Config.options?.bar.workspaces.showAppIcons && !!biggestWindow && AppSearch.iconExists(mainAppIconName),
                        root.dynamicSlots)
                    readonly property bool showLabel: face === "number"
                    readonly property bool showIcon: face === "icon"

                    StyledText { // Workspace number text
                        opacity: workspaceButtonBackground.showLabel ? 1 : 0
                        visible: opacity > 0
                        z: 3

                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2)
                            family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : defaultFont
                        }
                        text: Config.options?.bar.workspaces.numberMap[button.workspaceValue - 1] || button.workspaceValue
                        elide: Text.ElideRight
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue) ? 
                            root.barScheme.fg : 
                            (root.isOccupied(button.workspaceValue) ? root.barScheme.fg : 
                                root.barScheme.inactive)

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Rectangle { // Dot instead of ws number
                        id: wsDot
                        opacity: workspaceButtonBackground.face === "dot" ? (button.isNew ? 0.45 : 1) : 0
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: root.workspaceVisualSize * 0.18
                        height: width
                        radius: width / 2
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue) ? 
                            root.barScheme.fg : 
                            (root.isOccupied(button.workspaceValue) ? root.barScheme.fg : 
                                root.barScheme.inactive)

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Item { // Main app icon
                        anchors.centerIn: parent
                        width: root.workspaceVisualSize
                        height: root.workspaceVisualSize
                        opacity: workspaceButtonBackground.showIcon ? 1 : 0
                        visible: opacity > 0
                        AppIconPlate {
                            id: mainAppIcon
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (root.workspaceVisualSize - workspaceIconSize) / 2
                            anchors.rightMargin: (root.workspaceVisualSize - workspaceIconSize) / 2

                            iconName: workspaceButtonBackground.mainAppIconName
                            label: workspaceButtonBackground.biggestWindow?.class ?? ""
                            size: workspaceIconSize

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.bottomMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.rightMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on size {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        Loader {
                            active: Config.options.bar.workspaces.monochromeIcons
                            anchors.fill: mainAppIcon
                            sourceComponent: Item {
                                Desaturate {
                                    id: desaturatedIcon
                                    visible: false // There's already color overlay
                                    anchors.fill: parent
                                    source: mainAppIcon
                                    desaturation: 0.8
                                }
                                ColorOverlay {
                                    anchors.fill: desaturatedIcon
                                    source: desaturatedIcon
                                    color: ColorUtils.transparentize(wsDot.color, 0.9)
                                }
                            }
                        }
                    }
                }
                

            }

        }

    }

}
