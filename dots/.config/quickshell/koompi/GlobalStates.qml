import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool cheatsheetOpen: false
    property bool crosshairOpen: false
    property bool intelligenceOpen: false
    property bool launchpadOpen: false
    property bool settingsOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screensaverOpen: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool tourOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    // A bar status icon (Wi-Fi, battery, the mic light) opens the right panel on its own list; a second click closes it.
    signal sidebarRightModuleRequested(string name)
    function toggleSidebarRightOn(name: string): void {
        if (root.sidebarRightOpen)
            root.sidebarRightOpen = false;
        else
            root.sidebarRightModuleRequested(name);
    }

    onSidebarRightOpenChanged: {
        if (sidebarRightOpen) {
            Notifications.timeoutAll();
            seenTimer.restart();
        } else {
            seenTimer.stop();
        }
    }

    // read = panel stayed open long enough to be seen
    Timer {
        id: seenTimer
        interval: 1000
        onTriggered: Notifications.markAllRead()
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}