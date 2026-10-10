pragma Singleton
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import QtQuick
import Quickshell

/**
 * The optional modules: the quick-toggle types that are switches or modes and
 * not one-shot actions. Snip, colour picker, identify music and the on-screen
 * keyboard are Search commands (services/commandTree/Captures.qml), not modules.
 */
Singleton {
    id: root

    readonly property var types: ["screenRecord", "gameMode", "powerProfile", "easyEffects", "cloudflareWarp", "antiFlashbang", "mic"]

    function componentFor(type: string): Component {
        switch (type) {
        case "screenRecord": return recordModel;
        case "gameMode": return gameModel;
        case "powerProfile": return powerModel;
        case "easyEffects": return effectsModel;
        case "cloudflareWarp": return warpModel;
        case "antiFlashbang": return flashModel;
        case "mic": return micModel;
        }
        return null;
    }

    function listed(type: string): bool {
        return Config.options.controlCenter.extraModules.indexOf(type) >= 0;
    }

    function setListed(type: string, on: bool): void {
        const next = Array.from(Config.options.controlCenter.extraModules).filter(t => t !== type);
        if (on)
            next.push(type);
        Config.options.controlCenter.extraModules = next;
    }

    Component {
        id: recordModel
        QuickToggleModel {
            name: Translation.tr("Screen recording")
            icon: "videocam"
            hasStatusText: false
            toggled: ScreenRecording.active
            // the recorder's own picker cannot appear under the panel, and record.sh stops a running recording itself
            mainAction: () => {
                if (!ScreenRecording.active)
                    GlobalStates.controlCenterOpen = false;
                Quickshell.execDetached(["bash", "-c", 'sleep 0.3; exec "$@"', "koompi-record", Directories.recordScriptPath]);
            }
        }
    }
    Component { id: gameModel; GameModeToggle {} }
    Component { id: powerModel; PowerProfilesToggle {} }
    Component { id: effectsModel; EasyEffectsToggle {} }
    Component { id: warpModel; CloudflareWarpToggle {} }
    Component { id: flashModel; AntiFlashbangToggle {} }
    Component { id: micModel; MicToggle {} }
}
