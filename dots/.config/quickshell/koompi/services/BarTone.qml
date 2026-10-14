pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * How bright the wallpaper is under the bar, so the glass bar can tell how much tint its
 * text needs. The top strip of each wallpaper, scaled to fill the screen the way the
 * background draws it, is measured once per path in six columns - the bar's text sits in
 * parts of it, and parallax slides it sideways - as a gray mean and spread for each.
 * A bar asks with measure(path) and reads tones[path] when it lands.
 */
Singleton {
    id: root

    // path -> [{mean, sd}] per column, both 0..1 on gamma-encoded gray; null when unreadable
    property var tones: ({})
    property var queue: []

    function measure(path: string): void {
        if (path.length === 0 || root.tones[path] !== undefined || root.queue.includes(path))
            return;
        root.queue = root.queue.concat([path]);
        root.next();
    }

    function next(): void {
        if (probe.running || root.queue.length === 0)
            return;
        probe.path = root.queue[0];
        probe.running = true;
    }

    function settle(path: string, tone: var): void {
        const tones = Object.assign({}, root.tones);
        tones[path] = tone;
        root.tones = tones;
        root.queue = root.queue.filter(p => p !== path);
        root.next();
    }

    Process {
        id: probe
        property string path: ""
        // [0] keeps a GIF or a multi-frame file to one frame; the strip is the top 6% of a 16:10 fill
        command: ["magick", `${probe.path}[0]`, "-resize", "480x300^", "-gravity", "center", "-extent", "480x300",
            "-crop", "480x18+0+0", "+repage", "-colorspace", "Gray", "-crop", "6x1@", "+repage",
            "-format", "%[fx:mean] %[fx:standard_deviation]\\n", "info:"]
        stdout: StdioCollector {
            id: probeOut
        }
        onExited: (code, status) => {
            const columns = probeOut.text.trim().split("\n").map(line => line.trim().split(/\s+/).map(Number))
                .filter(parts => parts.length === 2 && parts.every(n => isFinite(n)))
                .map(parts => ({
                    "mean": parts[0],
                    "sd": parts[1]
                }));
            // unreadable (a video, a missing file): null keeps the bar solid
            root.settle(probe.path, code === 0 && columns.length === 6 ? columns : null);
        }
    }
}
