import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * The one-shot actions the Control Center does not carry (J20): each has a key,
 * and Search is where someone who forgot the key looks. Same entry shape as
 * Entries.qml; `bind` is the description of the Hyprland bind whose chord the row
 * shows.
 *
 * Search closes before these run, but the window is still on its way out when
 * Enter lands, so a capture waits a beat or it would photograph Search.
 */
QtObject {
    id: root

    readonly property real settleSeconds: 0.3

    function later(argv) {
        Quickshell.execDetached(["bash", "-c", `sleep ${root.settleSeconds}; exec "$@"`, "koompi-capture", ...argv]);
    }

    function shortcut(name) {
        root.later(["hyprctl", "dispatch", `hl.dsp.global("quickshell:${name}")`]);
    }

    readonly property var all: [
        ({
            id: "capture.snip",
            label: Translation.tr("Screen snip"),
            group: "capture",
            icon: "screenshot_region",
            keywords: "screenshot region capture grab picture",
            bind: "Utilities: Screen snip",
            execute: () => root.shortcut("regionScreenshot")
        }),
        ({
            id: "capture.record-region",
            label: Translation.tr("Record region"),
            group: "capture",
            icon: "videocam",
            keywords: "screen recording video capture",
            bind: "Utilities: Record region (no sound)",
            execute: () => root.shortcut("regionRecord")
        }),
        ({
            id: "capture.record-screen-sound",
            label: Translation.tr("Record screen with sound"),
            group: "capture",
            icon: "screen_record",
            keywords: "screen recording video capture audio fullscreen",
            bind: "Utilities: Record screen (with sound)",
            execute: () => root.later([Directories.recordScriptPath, "--fullscreen", "--sound"])
        }),
        ({
            id: "capture.color-picker",
            label: Translation.tr("Color picker"),
            group: "capture",
            icon: "colorize",
            keywords: "colour eyedropper hex pick pixel hyprpicker",
            bind: "Utilities: Pick a color and copy its hex code",
            execute: () => root.later(["hyprpicker", "-a"])
        }),
        ({
            id: "capture.identify-music",
            label: Translation.tr("Identify music"),
            group: "capture",
            icon: "music_cast",
            keywords: "song shazam recognise recognize listen songrec",
            // services/SongRec.qml:17 running, :19 toggleRunning
            state: () => SongRec.running ? Translation.tr("listening") : "",
            execute: () => SongRec.toggleRunning()
        }),
        ({
            id: "capture.on-screen-keyboard",
            label: Translation.tr("On-screen keyboard"),
            group: "capture",
            icon: "keyboard",
            keywords: "virtual osk touch type",
            bind: "Shell: Toggle on-screen keyboard",
            state: () => GlobalStates.oskOpen ? Translation.tr("on") : Translation.tr("off"),
            execute: () => {
                GlobalStates.oskOpen = !GlobalStates.oskOpen;
            }
        }),
        ({
            id: "capture.translate-screen",
            label: Translation.tr("Translate screen"),
            group: "capture",
            icon: "translate",
            keywords: "translation text language ocr overlay",
            bind: "Utilities: Translate screen content",
            execute: () => root.shortcut("screenTranslate")
        })
    ]
}
