pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common/functions/workspace-slots.js" as Slots
import "OverviewGrid.js" as Grid

// The desks, side by side, each with its tiles where they sit. Arrows move
// between desks, Enter goes, any printable key filters the windows.
Item {
    id: root
    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    readonly property var windowByAddress: HyprlandData.windowByAddress
    // Clamp to avoid lock-screen temp workspace (2147483647 - N) leaking into UI
    readonly property int activeId: Math.max(1, Math.min(100, root.monitor?.activeWorkspace?.id ?? 1))

    // a tile at least this wide (logical px) captures live; smaller ones capture one frame
    readonly property real liveMinWidth: 320
    readonly property int groupSize: 10
    readonly property real gap: 20
    readonly property real margin: 32

    readonly property var reserved: root.monitorData?.reserved ?? [0, 0, 0, 0]
    readonly property bool rotated: (root.monitorData?.transform ?? 0) % 2 === 1
    readonly property real deskWidth: Math.max(1, ((root.rotated ? root.monitorData?.height : root.monitorData?.width) ?? 1920) / (root.monitorData?.scale ?? 1) - root.reserved[0] - root.reserved[2])
    readonly property real deskHeight: Math.max(1, ((root.rotated ? root.monitorData?.width : root.monitorData?.height) ?? 1200) / (root.monitorData?.scale ?? 1) - root.reserved[1] - root.reserved[3])

    readonly property var deskWindows: HyprlandData.windowList.filter(w => w.mapped !== false && w.monitor === root.monitor?.id && w.workspace.id >= 1)
    readonly property var slotInfo: Slots.slots(root.deskWindows.map(w => w.workspace.id), root.activeId, root.groupSize)
    readonly property var slotIds: root.slotInfo.ids
    readonly property var shown: root.deskWindows.filter(w => root.slotIds.includes(w.workspace.id))

    readonly property real headerHeight: 64
    readonly property var layout: Grid.grid(root.slotIds.length, root.width - 2 * root.margin - root.reserved[0] - root.reserved[2], root.height - root.headerHeight - root.margin - root.reserved[1] - root.reserved[3], root.deskWidth / root.deskHeight, root.gap)
    readonly property real deskScale: root.layout.cellW / root.deskWidth

    property int selectedIndex: 0
    property string filter: ""
    property int matchIndex: 0
    property int dragTarget: -1
    readonly property bool filtering: root.filter.trim() !== ""

    readonly property var prepared: root.shown.map(w => ({
                name: Fuzzy.prepare(`${w.title} ${w.class}`),
                entry: w
            }))
    // Window titles run long enough that subsequence matching finds a query in almost any of them
    readonly property real scoreThreshold: 0.5
    readonly property var matches: root.filtering ? Fuzzy.go(root.filter.trim(), root.prepared, {
        all: true,
        key: "name",
        threshold: root.scoreThreshold
    }).map(r => r.obj.entry.address) : []
    readonly property string matchedAddress: root.matches[Math.min(root.matchIndex, root.matches.length - 1)] ?? ""

    function close() {
        GlobalStates.overviewOpen = false;
    }

    function goTo(id) {
        root.close();
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
    }

    function focusWindow(address) {
        root.close();
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
    }

    function activate() {
        if (root.filtering) {
            if (root.matchedAddress)
                root.focusWindow(root.matchedAddress);
        } else {
            root.goTo(root.slotIds[root.selectedIndex] ?? root.activeId);
        }
    }

    function move(direction) {
        if (root.filtering) {
            const delta = (direction === "left" || direction === "up") ? -1 : 1;
            root.matchIndex = Math.max(0, Math.min(root.matches.length - 1, root.matchIndex + delta));
        } else {
            root.selectedIndex = Grid.step(root.selectedIndex, direction, root.layout.cols, root.slotIds.length);
        }
    }

    function setFilter(text) {
        root.filter = text;
        root.matchIndex = 0;
    }

    function dropWindow(address) {
        const target = root.dragTarget;
        root.dragTarget = -1;
        const win = root.windowByAddress[address];
        if (target < 1 || !win || target === win.workspace.id)
            return;
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${target}, follow = false, window = "address:${address}" })`);
    }

    function snapshot() {
        const desks = [];
        for (let i = 0; i < deskRepeater.count; i++) {
            const d = deskRepeater.itemAt(i);
            desks.push({ id: d.deskId, isNew: d.isNew, selected: d.selected, x: d.x, y: d.y, w: d.width, h: d.height });
        }
        const tiles = [];
        for (let i = 0; i < tileRepeater.count; i++) {
            const t = tileRepeater.itemAt(i);
            tiles.push({ address: t.address, class: t.windowData?.class, desk: t.windowData?.workspace.id, x: t.x, y: t.y, w: t.width, h: t.height, visible: t.visible, live: t.live, selected: t.selected });
        }
        return { filter: root.filter, origin: { x: stage.x, y: stage.y }, desks: desks, tiles: tiles, matches: root.matches };
    }

    focus: true
    Component.onCompleted: {
        root.selectedIndex = Math.max(0, root.slotIds.indexOf(root.activeId));
        root.forceActiveFocus();
    }

    Keys.onPressed: event => {
        const keys = {};
        keys[Qt.Key_Left] = "left";
        keys[Qt.Key_Right] = "right";
        keys[Qt.Key_Up] = "up";
        keys[Qt.Key_Down] = "down";
        keys[Qt.Key_Tab] = "right";
        keys[Qt.Key_Backtab] = "left";
        if (event.key === Qt.Key_Escape) {
            if (root.filtering)
                root.setFilter("");
            else
                root.close();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate();
        } else if (keys[event.key]) {
            root.move(keys[event.key]);
        } else if (event.key === Qt.Key_Backspace) {
            root.setFilter(root.filter.slice(0, -1));
        } else if (event.text.length === 1 && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.setFilter(root.filter + event.text);
        } else {
            return;
        }
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: filterPill
        anchors {
            top: parent.top
            topMargin: root.reserved[1] + 12
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(420, root.width - 2 * root.margin)
        height: 44
        radius: height / 2
        color: Appearance.colors.colBackgroundSurfaceContainer
        border.width: root.filtering ? 2 : 1
        border.color: root.filtering ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)

        StyledText {
            anchors {
                fill: parent
                leftMargin: 20
                rightMargin: 20
            }
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: !root.filtering ? Translation.tr("Type to find a window") : (root.matches.length === 0 ? Translation.tr("No window matches %1").arg(root.filter) : root.filter)
            color: root.filtering ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
    }

    Item {
        id: stage
        anchors {
            fill: parent
            leftMargin: root.reserved[0] + root.margin
            topMargin: root.reserved[1] + root.headerHeight
            rightMargin: root.reserved[2] + root.margin
            bottomMargin: root.reserved[3] + root.margin
        }

        Repeater {
            id: deskRepeater
            model: root.slotIds
            delegate: OverviewDesk {
                id: desk
                required property int modelData
                required property int index
                deskId: modelData
                isNew: modelData === root.slotInfo.newId
                isActive: modelData === root.activeId
                selected: !root.filtering && index === root.selectedIndex
                dropHover: root.dragTarget === modelData
                x: Grid.cell(root.layout, index).x
                y: Grid.cell(root.layout, index).y
                width: root.layout.cellW
                height: root.layout.cellH
                onActivated: root.goTo(modelData)
                onDragEntered: root.dragTarget = modelData
                onDragExited: if (root.dragTarget === modelData)
                    root.dragTarget = -1
            }
        }

        Repeater {
            id: tileRepeater
            model: ScriptModel {
                values: ToplevelManager.toplevels.values.filter(tl => root.shown.some(w => w.address === `0x${tl.HyprlandToplevel?.address}`))
            }
            delegate: OverviewWindow {
                id: tile
                required property var modelData
                toplevel: modelData
                windowData: root.windowByAddress[`0x${modelData.HyprlandToplevel?.address}`]
                readonly property int deskIndex: root.slotIds.indexOf(windowData?.workspace.id)
                cell: deskIndex < 0 ? Qt.rect(0, 0, 0, 0) : Qt.rect(Grid.cell(root.layout, deskIndex).x, Grid.cell(root.layout, deskIndex).y, root.layout.cellW, root.layout.cellH)
                deskScale: root.deskScale
                originX: (root.monitorData?.x ?? 0) + root.reserved[0]
                originY: (root.monitorData?.y ?? 0) + root.reserved[1]
                liveMinWidth: root.liveMinWidth
                visible: deskIndex >= 0 && (!root.filtering || root.matches.includes(address))
                selected: root.filtering && address === root.matchedAddress
                showTitle: root.filtering
                onPicked: address => root.focusWindow(address)
                onReleased: address => root.dropWindow(address)
            }
        }
    }
}
