import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    spacing: Appearance.spacing.small

    property var brightnessMonitor: null

    CcRow {
        objectName: "cc-nightLightNow"
        icon: "bedtime"
        title: Translation.tr("Night Light")
        detail: Translation.tr("Warmer colours for the evening")
        toggled: Hyprsunset.temperatureActive
        onActivated: Hyprsunset.toggleTemperature()
    }

    CcRow {
        icon: "night_sight_auto"
        title: Translation.tr("Automatic")
        detail: Translation.tr("From sunset to sunrise")
        toggled: Config.options.light.night.automatic
        onActivated: Config.options.light.night.automatic = !Config.options.light.night.automatic
    }

    WindowDialogSlider {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.small
        Layout.rightMargin: Appearance.spacing.small
        text: Translation.tr("Night Light warmth")
        from: 6500
        to: 1200
        stopIndicatorValues: [5000, to]
        value: Config.options.light.night.colorTemperature
        onMoved: Config.options.light.night.colorTemperature = value
        tooltipContent: `${Math.round(value)}K`
    }

    WindowDialogSlider {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.small
        Layout.rightMargin: Appearance.spacing.small
        text: Translation.tr("Brightness")
        value: root.brightnessMonitor?.brightness ?? 0
        onMoved: root.brightnessMonitor?.setBrightness(value)
    }

    WindowDialogSlider {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.small
        Layout.rightMargin: Appearance.spacing.small
        text: Translation.tr("Gamma")
        from: Hyprsunset.gammaLowerLimit / 100
        value: Hyprsunset.gamma / 100
        onMoved: Hyprsunset.setGamma(value * 100)
        tooltipContent: `${Math.round(value * 100)}%`
    }

    CcLinkRow {
        buttonText: Translation.tr("More display settings")
        page: "displays"
    }

    Item {
        Layout.fillHeight: true
    }
}
