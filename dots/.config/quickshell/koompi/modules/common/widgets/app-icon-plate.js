.pragma library

// body box of a theme's full-bleed icons, as fractions of the canvas; a theme not listed here is never masked
const BODY_BOXES = {
    "WhiteSur-green": { lo: 0.0625, hi: 0.9375 },
    "koompi-icons": { lo: 0.0625, hi: 0.9375 },
    "koompi-icons-dark": { lo: 0.0625, hi: 0.9375 }
};
const SIZES = [16, 24, 32, 48, 64, 96, 128, 192, 256];
// control handle of a cubic that follows the exponent-2.5 corner of rounding_power within 0.5 %
const CORNER_HANDLE = 0.6877;
const RADIUS_RATIO = 0.28;
const GLYPH_RATIO = 0.72;

function bodyThemes() { return Object.keys(BODY_BOXES); }
function radiusRatio() { return RADIUS_RATIO; }
function cornerHandle() { return CORNER_HANDLE; }
function glyphRatio() { return GLYPH_RATIO; }

function bodyBox(theme, inTheme) {
    const box = BODY_BOXES[theme];
    return box && inTheme ? { lo: box.lo, hi: box.hi } : null;
}

function parseIndex(text) {
    const lines = (text || "").split("\n");
    const names = {};
    for (let i = 1; i < lines.length; i++)
        if (lines[i]) names[lines[i]] = true;
    return { theme: lines[0] || "", names: names };
}

function unresolved(name) {
    return !name || name.indexOf("image-missing") >= 0;
}

function bucket(size) {
    for (let i = 0; i < SIZES.length; i++)
        if (SIZES[i] >= size) return SIZES[i];
    return SIZES[SIZES.length - 1];
}

function letter(label) {
    const m = /[A-Za-z0-9À-￿]/.exec(label || "");
    return m ? m[0].toUpperCase() : "?";
}

function shadowMargin(side) {
    return Math.ceil(Math.min(Math.max(side * 0.09, 4), 10) * 1.6) + 1;
}
