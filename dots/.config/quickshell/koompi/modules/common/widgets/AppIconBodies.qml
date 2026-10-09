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
        command: ["bash", "-c", `
            theme=\${QS_ICON_THEME:-$(awk -F= '/^\\[/ { s = $0 } s == "[Icons]" && $1 == "Theme" { print $2 }' "\${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals" 2> /dev/null)}
            echo "$theme"
            [[ -n $theme ]] || exit 0
            for base in "\${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons" \${XDG_DATA_DIRS//://icons }/icons; do
                [[ -d $base/$theme ]] || continue
                for category in apps devices; do ls -1 "$base/$theme/$category/scalable" 2> /dev/null; done | sed 's/\\.[^.]*$//'
                break
            done
        `]
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
