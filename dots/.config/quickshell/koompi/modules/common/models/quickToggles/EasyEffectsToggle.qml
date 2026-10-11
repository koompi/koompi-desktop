import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    // EasyEffects' input chain is RNNoise (the seeded easyeffectsrc), so the toggle is named for what it does
    name: Translation.tr("Mic noise reduction")
    statusText: Translation.tr("Cleans up your voice on calls")

    available: EasyEffects.available
    toggled: EasyEffects.active
    icon: "graphic_eq"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    mainAction: () => {
        EasyEffects.toggle()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "flatpak run com.github.wwmm.easyeffects || easyeffects"])
        GlobalStates.sidebarRightOpen = false
    }

    tooltipText: Translation.tr("Mic noise reduction | Right-click to open EasyEffects")
}
