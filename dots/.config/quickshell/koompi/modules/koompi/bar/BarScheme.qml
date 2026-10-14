import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * The colours of everything drawn straight on the bar. Over the solid bar, or glass in the
 * theme's own tone, they are the theme's bar tokens. Over glass of the other tone - dark text
 * on a bright wallpaper in dark mode, the way the macOS menu bar turns - they are a neutral
 * set built the same way for that tone. BarContent picks the tone; a widget reads its window's
 * scheme, or its own unflipped one outside a bar.
 */
QtObject {
    property bool flipped: false

    readonly property bool lightText: Appearance.m3colors.darkmode !== flipped
    // the opaque colour of the glass in each tone: the solid bar's own colours
    readonly property color glass: lightText ? Qt.rgba(8 / 255, 20 / 255, 14 / 255, 1) : Qt.rgba(246 / 255, 248 / 255, 251 / 255, 1)
    readonly property color ink: lightText ? "#f2f5f3" : "#141816"

    readonly property color fg: flipped ? ink : Appearance.colors.colOnLayer0
    readonly property color subtext: flipped ? ColorUtils.mix(ink, glass, 0.8) : Appearance.colors.colBarSubtext
    readonly property color inactive: flipped ? ColorUtils.mix(ink, glass, 0.7) : Appearance.colors.colBarTextInactive
    readonly property color element: flipped ? ColorUtils.transparentize(ink, 0.93) : Appearance.colors.colBarElementBackground
    readonly property color elementActive: flipped ? ColorUtils.transparentize(ink, 0.84) : Appearance.colors.colBarElementBackgroundActive
    readonly property color hover: flipped ? ColorUtils.transparentize(ink, 0.9) : Appearance.colors.colLayer1Hover
    readonly property color pressed: flipped ? ColorUtils.transparentize(ink, 0.8) : Appearance.colors.colLayer1Active
    readonly property color group: flipped ? ColorUtils.transparentize(ink, 0.9) : Appearance.colors.colLayer1
    readonly property color separator: flipped ? ColorUtils.transparentize(ink, 0.8) : Appearance.colors.colOutlineVariant
    readonly property color worstCase: flipped ? glass : Appearance.colors.colBarWorstCase

    function luminance(c: color): real {
        const lin = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }
    function contrast(a: color, b: color): real {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    // The least tint of this glass, floor..1 in twentieths, at which its faintest text (the
    // inactive colour) keeps 4.5:1 over the blurred wallpaper's worst column: one spread
    // brighter under light text, one darker under dark text. 1 when nothing short of solid will.
    function tintOver(columns: var, floor: real): real {
        const wall = lightText ? Math.max(...columns.map(c => Math.min(1, c.mean + c.sd)))
            : Math.min(...columns.map(c => Math.max(0, c.mean - c.sd)));
        for (let step = Math.round(floor * 20); step <= 20; step++) {
            const a = step / 20;
            const under = Qt.rgba(a * glass.r + (1 - a) * wall, a * glass.g + (1 - a) * wall, a * glass.b + (1 - a) * wall, 1);
            if (contrast(inactive, under) >= 4.5)
                return a;
        }
        return 1;
    }
}
