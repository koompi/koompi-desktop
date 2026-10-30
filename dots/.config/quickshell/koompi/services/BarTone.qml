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
 * The same pass cuts the whole fill into ten bands of six tiles, for the menus that hang
 * from the bar over the wallpaper below it: under(path, top, bottom).
 */
Singleton {
    id: root

    // path -> [{mean, sd}] per column, both 0..1 on gamma-encoded gray; null when unreadable
    property var tones: ({})
    // path -> ten bands, top down, each six tiles as tones has them; null when unreadable
    property var bands: ({})
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

    // The tiles of every band from top to bottom, both fractions of the screen's height: whole
    // bands, all six tiles, as the bar takes all six columns. null until path is measured.
    function under(path: string, top: real, bottom: real): var {
        const rows = root.bands[path];
        if (!rows)
            return null;
        const first = Math.max(0, Math.min(rows.length - 1, Math.floor(top * rows.length)));
        const last = Math.max(first, Math.min(rows.length - 1, Math.ceil(bottom * rows.length) - 1));
        return [].concat(...rows.slice(first, last + 1));
    }

    function settle(path: string, tone: var, rows: var): void {
        const tones = Object.assign({}, root.tones);
        tones[path] = tone;
        const bands = Object.assign({}, root.bands);
        bands[path] = rows;
        root.bands = bands;
        root.tones = tones;
        root.queue = root.queue.filter(p => p !== path);
        root.next();
    }

    Process {
        id: probe
        property string path: ""
        // [0] keeps a GIF or a multi-frame file to one frame. The strip is the top 6% of a 16:10
        // fill, six tiles; then the bands, sixty tiles row by row. +gravity: a crop honours the
        // gravity the fill set, and with it the "top" strip was cut from the middle of the picture.
        command: ["magick", `${probe.path}[0]`, "-resize", "480x300^", "-gravity", "center", "-extent", "480x300", "+gravity",
            "-colorspace", "Gray", "-write", "mpr:fill", "+delete",
            "(", "mpr:fill", "-crop", "480x18+0+0", "+repage", "-crop", "6x1@", "+repage", ")",
            "(", "mpr:fill", "-crop", "6x10@", "+repage", ")",
            "-format", "%[fx:mean] %[fx:standard_deviation]\\n", "info:"]
        stdout: StdioCollector {
            id: probeOut
        }
        onExited: (code, status) => {
            const tiles = probeOut.text.trim().split("\n").map(line => line.trim().split(/\s+/).map(Number))
                .filter(parts => parts.length === 2 && parts.every(n => isFinite(n)))
                .map(parts => ({
                    "mean": parts[0],
                    "sd": parts[1]
                }));
            // unreadable (a video, a missing file): null keeps the bar solid, and its menus
            const read = code === 0 && tiles.length === 66;
            const rows = [];
            for (let i = 6; read && i < 66; i += 6)
                rows.push(tiles.slice(i, i + 6));
            root.settle(probe.path, read ? tiles.slice(0, 6) : null, read ? rows : null);
        }
    }
}
