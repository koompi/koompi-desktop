import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Flickable {
    id: root

    property alias column: column
    property var brightnessMonitor: null
    signal openPage(string name)

    function reveal(item): void {
        if (!item || !column.contains(column.mapFromItem(item, 0, 0)))
            return;
        const top = item.mapToItem(column, 0, 0).y;
        const bottom = top + item.height;
        if (top < root.contentY)
            root.contentY = Math.max(0, top - Appearance.spacing.normal);
        else if (bottom > root.contentY + root.height)
            root.contentY = Math.min(root.contentHeight - root.height, bottom - root.height + Appearance.spacing.normal);
    }

    function focusFirst(): void {
        column.children.find(item => item.visible && item.activeFocusOnTab)?.forceActiveFocus(Qt.TabFocusReason);
    }

    clip: true
    contentWidth: width
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    implicitHeight: column.implicitHeight

    Component.onCompleted: Hyprsunset.fetchState()

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            root.reveal(root.Window.window.activeFocusItem);
        }
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: Appearance.spacing.small

        CcRow {
            objectName: "cc-wifi"
            icon: Network.materialSymbol
            title: Translation.tr("Wi-Fi")
            detail: Network.wifiEnabled ? (Network.networkName || Translation.tr("Not connected")) : ""
            toggled: Network.wifiEnabled
            hasDetail: true
            onActivated: Network.toggleWifi()
            onOpened: root.openPage("wifi")
        }

        CcRow {
            objectName: "cc-bluetooth"
            visible: BluetoothStatus.available
            icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            title: Translation.tr("Bluetooth")
            detail: BluetoothStatus.enabled ? (BluetoothStatus.firstActiveDevice?.alias ?? Translation.tr("Not connected")) : ""
            toggled: BluetoothStatus.enabled
            hasDetail: true
            onActivated: BluetoothStatus.setEnabled(!BluetoothStatus.enabled)
            onOpened: root.openPage("bluetooth")
        }

        CcRow {
            objectName: "cc-dnd"
            icon: "do_not_disturb_on"
            title: Translation.tr("Do Not Disturb")
            toggled: Notifications.silent
            onActivated: Notifications.silent = !Notifications.silent
        }

        CcRow {
            objectName: "cc-keepAwake"
            icon: "coffee"
            title: Translation.tr("Keep awake")
            toggled: Idle.inhibit
            onActivated: Idle.toggleInhibit()
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

        CcRow {
            objectName: "cc-nightLight"
            icon: Config.options.light.night.automatic ? "night_sight_auto" : "bedtime"
            title: Translation.tr("Night Light")
            detail: Config.options.light.night.automatic ? Translation.tr("Automatic") : ""
            toggled: Hyprsunset.temperatureActive
            hasDetail: true
            onActivated: Hyprsunset.toggleTemperature()
            onOpened: root.openPage("display")
        }

        CcRow {
            objectName: "cc-darkMode"
            icon: DarkMode.automatic ? "brightness_auto" : "contrast"
            title: Translation.tr("Dark mode")
            detail: DarkMode.automatic ? Translation.tr("Automatic") : ""
            toggled: DarkMode.dark
            onActivated: DarkMode.toggle()
        }

        CcSliderRow {
            objectName: "cc-sound"
            icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
            title: Translation.tr("Sound")
            detail: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output device")
            value: Audio.sink?.audio?.volume ?? 0
            hasDetail: true
            onMoved: v => {
                if (Audio.sink?.audio)
                    Audio.sink.audio.volume = v;
            }
            onOpened: root.openPage("sound")
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
            delegate: CcExtraRow {
                required property string modelData
                type: modelData
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
