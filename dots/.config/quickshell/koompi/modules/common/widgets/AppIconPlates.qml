pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Plates and masked icons are drawn once into a texture here and every AppIconPlate reuses it.
Singleton {
    id: root

    property var urls: ({})
    property var held: ({})
    property var pending: ({})
    property int revision: 0
    property int baseRenders: 0
    property int maskRenders: 0
    property string scheme: ""

    function url(key: string): string {
        return root.revision >= 0 ? (root.urls[key] ?? "") : "";
    }

    function purge(prefix: string): void {
        for (const key of Object.keys(root.urls)) {
            if (!key.startsWith(prefix)) continue;
            delete root.urls[key];
            delete root.held[key];
        }
    }

    function claim(key: string, scheme: string): bool {
        if (root.urls[key] || root.pending[key]) return false;
        if (key.startsWith("base:") && scheme !== root.scheme) {
            root.purge("base:");
            root.scheme = scheme;
        }
        root.pending[key] = true;
        return true;
    }

    function store(key: string, result): void {
        root.held[key] = result;
        root.urls[key] = result.url.toString();
        delete root.pending[key];
        if (key.startsWith("base:")) root.baseRenders++;
        else root.maskRenders++;
        root.revision++;
    }

    function abandon(key: string): void {
        if (!root.pending[key]) return;
        delete root.pending[key];
        root.revision++;
    }

    IpcHandler {
        target: "appIconPlates"

        function stats(): string {
            return `base=${root.baseRenders} mask=${root.maskRenders} cached=${Object.keys(root.urls).length}`;
        }
    }
}
