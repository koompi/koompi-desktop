import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    property alias column: column
    property var brightnessMonitor: null
    // the row whose list is open: "wifi", "bluetooth", "sound", "power" or ""
    property string expanded: ""
    signal openPage(string name)

    readonly property var owners: ({
            "wifi": wifiRow,
            "bluetooth": bluetoothRow,
            "sound": soundRow,
            "power": powerRow
        })

    function toggleExpanded(name: string): void {
        root.expanded = root.expanded === name ? "" : name;
    }

    // folds the open list and hands the keys back to its row; false when none was open
    function fold(): bool {
        const name = root.expanded;
        if (name.length === 0)
            return false;
        root.expanded = "";
        root.owners[name]?.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    function focusFirst(): void {
        wifiRow.forceActiveFocus(Qt.TabFocusReason);
    }

    function stops(): var {
        const out = [];
        const seen = new Set();
        const walk = item => {
            if (!item || seen.has(item) || !item.visible)
                return;
            seen.add(item);
            if (item.activeFocusOnTab && !item.tabOnly)
                out.push(item);
            for (const child of item.children ?? [])
                walk(child);
        };
        walk(root.column);
        return out;
    }

    // the arrows move across the grid as well as down it; false leaves the key to the panel
    function navigate(dx: int, dy: int): bool {
        const from = root.Window.window?.activeFocusItem;
        const all = root.stops();
        if (!from || all.indexOf(from) < 0)
            return false;
        const at = item => item.mapToItem(root, item.width / 2, item.height / 2);
        const here = at(from);
        let best = null;
        let bestScore = Infinity;
        for (const item of all) {
            if (item === from)
                continue;
            const p = at(item);
            const ax = dx !== 0 ? (p.x - here.x) * dx : 0;
            const ay = dy !== 0 ? (p.y - here.y) * dy : 0;
            const across = dx !== 0 ? Math.abs(p.y - here.y) : Math.abs(p.x - here.x);
            if (dx !== 0 && (ax <= 0 || across > 8))
                continue;
            if (dy !== 0 && ay <= 8)
                continue;
            const score = (dx !== 0 ? ax : ay) * 4 + across;
            if (score < bestScore) {
                bestScore = score;
                best = item;
            }
        }
        if (!best)
            return false;
        best.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    Keys.onPressed: event => {
        const dirs = {};
        dirs[Qt.Key_Left] = [-1, 0];
        dirs[Qt.Key_Right] = [1, 0];
        dirs[Qt.Key_Up] = [0, -1];
        dirs[Qt.Key_Down] = [0, 1];
        const d = dirs[event.key];
        if (d && root.navigate(d[0], d[1]))
            event.accepted = true;
    }

    implicitHeight: column.implicitHeight

    Component.onCompleted: Hyprsunset.fetchState()

    ColumnLayout {
        id: column
        width: root.width
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.small
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
                text: Translation.tr("Quick settings")
            }
            CcIconButton {
                objectName: "cc-edit"
                glyph: "edit"
                label: Translation.tr("Edit the optional modules")
                onClicked: root.openPage("edit")
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Appearance.spacing.small
            rowSpacing: Appearance.spacing.small
            uniformCellWidths: true

            CcRow {
                id: wifiRow
                objectName: "cc-wifi"
                tile: true
                Layout.columnSpan: bluetoothRow.visible ? 1 : 2
                icon: Network.materialSymbol
                title: Translation.tr("Wi-Fi")
                detail: Network.wifiEnabled ? (Network.networkName || Translation.tr("Not connected")) : Translation.tr("Off")
                toggled: Network.wifiEnabled
                expandable: true
                hasSwitch: true
                expanded: root.expanded === "wifi"
                onActivated: Network.toggleWifi()
                onOpened: root.toggleExpanded("wifi")
            }
            CcRow {
                id: bluetoothRow
                objectName: "cc-bluetooth"
                tile: true
                visible: BluetoothStatus.available
                icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                title: Translation.tr("Bluetooth")
                detail: BluetoothStatus.enabled ? (BluetoothStatus.firstActiveDevice?.alias ?? Translation.tr("Not connected")) : Translation.tr("Off")
                toggled: BluetoothStatus.enabled
                expandable: true
                hasSwitch: true
                expanded: root.expanded === "bluetooth"
                onActivated: BluetoothStatus.setEnabled(!BluetoothStatus.enabled)
                onOpened: root.toggleExpanded("bluetooth")
            }
            CcExpansion {
                objectName: "cc-list-wifi"
                Layout.columnSpan: 2
                open: root.expanded === "wifi"
                bodyHeight: 230
                sourceComponent: CcWifiPage {}
            }
            CcExpansion {
                objectName: "cc-list-bluetooth"
                Layout.columnSpan: 2
                open: root.expanded === "bluetooth" && BluetoothStatus.available
                bodyHeight: 230
                sourceComponent: CcBluetoothPage {}
            }

            CcRow {
                id: soundRow
                objectName: "cc-sound"
                tile: true
                Layout.columnSpan: powerRow.visible ? 1 : 2
                icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                title: Translation.tr("Sound")
                detail: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output device")
                toggled: !(Audio.sink?.audio?.muted ?? true)
                expandable: true
                hasSwitch: true
                expanded: root.expanded === "sound"
                onActivated: {
                    if (Audio.sink?.audio)
                        Audio.sink.audio.muted = !Audio.sink.audio.muted;
                }
                onOpened: root.toggleExpanded("sound")
            }
            CcExtraRow {
                id: powerRow
                type: "powerProfile"
                tile: !editing
                expandable: true
                expanded: root.expanded === "power"
                onOpened: root.toggleExpanded("power")
            }
            CcExpansion {
                objectName: "cc-list-sound"
                Layout.columnSpan: 2
                open: root.expanded === "sound"
                sourceComponent: CcSoundPage {}
            }
            CcExpansion {
                objectName: "cc-list-power"
                Layout.columnSpan: 2
                open: root.expanded === "power" && powerRow.visible
                sourceComponent: CcPowerPage {}
            }

            CcRow {
                objectName: "cc-dnd"
                tile: true
                icon: "do_not_disturb_on"
                title: Translation.tr("Do Not Disturb")
                toggled: Notifications.silent
                onActivated: Notifications.silent = !Notifications.silent
            }
            CcRow {
                objectName: "cc-keepAwake"
                tile: true
                icon: "coffee"
                title: Translation.tr("Keep awake")
                toggled: Idle.inhibit
                onActivated: Idle.toggleInhibit()
            }
            CcRow {
                objectName: "cc-nightLight"
                tile: true
                icon: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
                title: Translation.tr("Night Light")
                toggled: Hyprsunset.temperatureActive
                onActivated: Hyprsunset.toggleTemperature()
            }
            CcRow {
                objectName: "cc-darkMode"
                tile: true
                icon: DarkMode.automatic ? "brightness_auto" : "contrast"
                title: Translation.tr("Dark mode")
                toggled: DarkMode.dark
                onActivated: DarkMode.toggle()
            }

            Repeater {
                model: Config.options.controlCenter.extraModules.filter(t => t !== "powerProfile")
                delegate: CcExtraRow {
                    required property string modelData
                    type: modelData
                    tile: true
                }
            }
        }

        CcSliderRow {
            objectName: "cc-brightness"
            icon: "light_mode"
            title: Translation.tr("Brightness")
            value: root.brightnessMonitor?.brightness ?? 0
            hasDetail: true
            onMoved: v => root.brightnessMonitor?.setBrightness(v)
            onOpened: root.openPage("display")
        }

        CcSliderRow {
            objectName: "cc-volume"
            icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            title: Translation.tr("Volume")
            value: Audio.sink?.audio?.volume ?? 0
            onMoved: v => {
                if (Audio.sink?.audio)
                    Audio.sink.audio.volume = v;
            }
        }

        Loader {
            Layout.fillWidth: true
            active: MprisController.hasActiveMedia
            visible: active
            sourceComponent: CcRow {
                objectName: "cc-nowPlaying"
                hasToggle: false
                hasDetail: true
                icon: "music_note"
                title: MprisController.activePlayer?.trackTitle || Translation.tr("Now playing")
                detail: `${MprisController.isPlaying ? Translation.tr("Playing") : Translation.tr("Paused")}${MprisController.activePlayer?.trackArtist ? " · " + MprisController.activePlayer.trackArtist : ""}`
                onOpened: root.openPage("nowPlaying")
                trailing: [
                    CcIconButton {
                        glyph: MprisController.isPlaying ? "pause" : "play_arrow"
                        label: MprisController.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        onClicked: MprisController.togglePlaying()
                    },
                    CcIconButton {
                        glyph: "skip_next"
                        label: Translation.tr("Next")
                        onClicked: MprisController.next()
                    }
                ]
            }
        }

        Loader {
            Layout.fillWidth: true
            active: Battery.available
            visible: active
            sourceComponent: CcRow {
                objectName: "cc-battery"
                hasToggle: false
                hasDetail: true
                icon: Battery.isCharging ? "battery_charging_full" : "battery_full"
                title: Translation.tr("Battery")
                detail: `${Math.round(Battery.percentage * 100)}%${Battery.isCharging ? " · " + Translation.tr("Charging") : ""}${ChargeLimit.enabled ? " · " + Translation.tr("Limit %1%").arg(ChargeLimit.endThreshold) : ""}`
                onOpened: root.openPage("battery")
            }
        }
    }
}
