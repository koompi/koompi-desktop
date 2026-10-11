pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "app-icon-plate.js" as Plate

// Which app icons the active icon theme draws itself, read once from its own app and device folders.
Singleton {
    id: root

    property string theme: ""
    property var names: ({})
    property int revision: 0

    function box(name: string): var {
        return root.revision >= 0 ? Plate.bodyBox(root.theme, root.names[name] === true) : null;
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
}
