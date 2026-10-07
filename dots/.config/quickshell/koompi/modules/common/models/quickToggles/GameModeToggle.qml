import qs.services

QuickToggleModel {
    name: Translation.tr("Game mode")
    toggled: HyprlandModes.gameMode
    icon: "gamepad"

    mainAction: () => {
        HyprlandModes.gameMode = !HyprlandModes.gameMode;
    }

    tooltipText: Translation.tr("Game mode")
}
