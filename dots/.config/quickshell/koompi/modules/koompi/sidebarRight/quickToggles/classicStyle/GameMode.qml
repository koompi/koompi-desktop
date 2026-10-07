import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    buttonIcon: "gamepad"
    toggled: HyprlandModes.gameMode

    onClicked: HyprlandModes.gameMode = !HyprlandModes.gameMode

    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}
