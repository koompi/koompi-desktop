pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool built: surface.item !== null

    function dismiss() {
        GlobalStates.screenTranslatorOpen = false
    }

    readonly property var currentScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    property var lockedScreen

    LazySurface {
        id: surface
        open: GlobalStates.screenTranslatorOpen
        keepWarm: 0

        component: ScreenTranslatorPanel {
            screen: root.lockedScreen
            onDismiss: root.dismiss()
        }
    }

    function translate() {
        if (!GlobalStates.screenTranslatorOpen)
            root.lockedScreen = root.currentScreen
        GlobalStates.screenTranslatorOpen = true
    }

    IpcHandler {
        target: "screenTranslator"

        function translate() {
            root.translate()
        }
    }

    GlobalShortcut {
        name: "screenTranslate"
        description: "Translates screen content"
        onPressed: root.translate()
    }
}
