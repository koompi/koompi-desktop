pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "app-icon-plate.js" as Plate

// Which app icons the active icon theme draws itself, read once from its own app and device folders, and the
// icon each app ships itself, which a bare icon draws instead of the theme's full-bleed tile.
Singleton {
    id: root

    property string theme: ""
    property var names: ({})
    property var own: ({})
    property int revision: 0

    function box(name: string): var {
        return root.revision >= 0 ? Plate.bodyBox(root.theme, root.names[name] === true) : null;
    }

    // the app's own icon for a name the theme draws as a full-bleed tile, else ""
    function ownPath(name: string): string {
        return root.box(name) !== null ? (root.own[name] ?? "") : "";
    }

    Process {
        running: true
        command: ["bash", Quickshell.shellPath("scripts/colors/icon_theme_index.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = Plate.parseIndex(this.text);
                root.theme = parsed.theme;
                root.names = parsed.names;
                root.revision++;
            }
        }
    }

    Process {
        running: true
        command: ["bash", Quickshell.shellPath("scripts/colors/app_own_icons.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.own = Plate.parseOwn(this.text);
                root.revision++;
            }
        }
    }
}
