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
    property var powerRow: null
    signal openPage(string name)

    readonly property var owners: ({
            "wifi": wifiRow,
            "bluetooth": bluetoothRow,
            "sound": soundRow
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
        (root.owners[name] ?? root.powerRow)?.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    function focusFirst(): void {
        wifiRow.forceActiveFocus(Qt.TabFocusReason);
    }

    implicitHeight: column.implicitHeight

    Component.onCompleted: Hyprsunset.fetchState()

    ColumnLayout {
        id: column
        width: root.width
        spacing: Appearance.spacing.small

        CcRow {
            id: wifiRow
            objectName: "cc-wifi"
            icon: Network.materialSymbol
            title: Translation.tr("Wi-Fi")
            detail: Network.wifiEnabled ? (Network.networkName || Translation.tr("Not connected")) : ""
            toggled: Network.wifiEnabled
            expandable: true
            hasSwitch: true
            expanded: root.expanded === "wifi"
            onActivated: Network.toggleWifi()
            onOpened: root.toggleExpanded("wifi")
        }
        CcExpansion {
            objectName: "cc-list-wifi"
            open: root.expanded === "wifi"
            bodyHeight: 230
            sourceComponent: CcWifiPage {}
        }

        CcRow {
            id: bluetoothRow
            objectName: "cc-bluetooth"
            visible: BluetoothStatus.available
            icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            title: Translation.tr("Bluetooth")
            detail: BluetoothStatus.enabled ? (BluetoothStatus.firstActiveDevice?.alias ?? Translation.tr("Not connected")) : ""
            toggled: BluetoothStatus.enabled
            expandable: true
            hasSwitch: true
            expanded: root.expanded === "bluetooth"
            onActivated: BluetoothStatus.setEnabled(!BluetoothStatus.enabled)
            onOpened: root.toggleExpanded("bluetooth")
        }
        CcExpansion {
            objectName: "cc-list-bluetooth"
            open: root.expanded === "bluetooth" && BluetoothStatus.available
            bodyHeight: 230
            sourceComponent: CcBluetoothPage {}
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Appearance.spacing.small
            rowSpacing: Appearance.spacing.small
            uniformCellWidths: true

            CcRow {
                objectName: "cc-dnd"
                stackState: true
                icon: "do_not_disturb_on"
                title: Translation.tr("Do Not Disturb")
                toggled: Notifications.silent
                onActivated: Notifications.silent = !Notifications.silent
            }

            CcRow {
                objectName: "cc-keepAwake"
                stackState: true
                icon: "coffee"
                title: Translation.tr("Keep awake")
                toggled: Idle.inhibit
                onActivated: Idle.toggleInhibit()
            }

            CcRow {
                objectName: "cc-nightLight"
                stackState: true
                icon: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
                title: Translation.tr("Night Light")
                toggled: Hyprsunset.temperatureActive
                hasDetail: true
                onActivated: Hyprsunset.toggleTemperature()
                onOpened: root.openPage("display")
            }

            CcRow {
                objectName: "cc-darkMode"
                stackState: true
                icon: DarkMode.automatic ? "brightness_auto" : "contrast"
                title: Translation.tr("Dark mode")
                toggled: DarkMode.dark
                onActivated: DarkMode.toggle()
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
            id: soundRow
            objectName: "cc-sound"
            icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            title: Translation.tr("Sound")
            detail: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output device")
            value: Audio.sink?.audio?.volume ?? 0
            hasDetail: true
            expandable: true
            expanded: root.expanded === "sound"
            onMoved: v => {
                if (Audio.sink?.audio)
                    Audio.sink.audio.volume = v;
            }
            onOpened: root.toggleExpanded("sound")
        }
        CcExpansion {
            objectName: "cc-list-sound"
            open: root.expanded === "sound"
            sourceComponent: CcSoundPage {}
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

        Repeater {
            model: Config.options.controlCenter.extraModules
            delegate: ColumnLayout {
                id: extra
                required property string modelData
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                CcExtraRow {
                    id: extraRow
                    type: extra.modelData
                    expandable: extra.modelData === "powerProfile"
                    expanded: root.expanded === "power"
                    onOpened: root.toggleExpanded("power")
                    Component.onCompleted: if (expandable)
                        root.powerRow = extraRow
                }
                CcExpansion {
                    objectName: "cc-list-power"
                    open: extra.modelData === "powerProfile" && root.expanded === "power"
                    sourceComponent: CcPowerPage {}
                }
            }
        }

        CcRow {
            objectName: "cc-edit"
            hasToggle: false
            hasDetail: true
            icon: "edit"
            title: Translation.tr("Edit")
            detail: Translation.tr("Choose the optional modules")
            onOpened: root.openPage("edit")
        }
    }
}
