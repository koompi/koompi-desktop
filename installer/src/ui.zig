//! ui.zig - a cell grid drawn with plain ANSI, sized for an 80x25 VGA
//! console. 16 colors only, bold for bright (what TERM=linux does), ASCII
//! and box-drawing glyphs only.

const std = @import("std");
const sys = @import("sys.zig");

pub const Style = enum(u8) {
    text,
    strong,
    dim,
    accent,
    header,
    select,
    field,
    field_focus,
    danger,
    ok,
    warn,
};

pub var no_color = false;

fn sgr(s: Style) []const u8 {
    if (no_color) return switch (s) {
        .header, .select, .field_focus => "\x1b[0;7m",
        .strong, .danger, .accent, .ok, .warn => "\x1b[0;1m",
        else => "\x1b[0m",
    };
    return switch (s) {
        .text => "\x1b[0;37;40m",
        .strong => "\x1b[0;1;37;40m",
        .dim => "\x1b[0;90;40m",
        .accent => "\x1b[0;1;36;40m",
        .header => "\x1b[0;1;37;44m",
        .select => "\x1b[0;30;46m",
        .field => "\x1b[0;1;37;40m",
        .field_focus => "\x1b[0;1;37;44m",
        .danger => "\x1b[0;1;31;40m",
        .ok => "\x1b[0;1;32;40m",
        .warn => "\x1b[0;1;33;40m",
    };
}

/// Box drawing is in every console font; anything else non-ASCII may not be.
fn consoleSafe(cp: u21) bool {
    return cp < 0x80 or (cp >= 0x2500 and cp <= 0x257f);
}

pub const Cell = struct { ch: u21 = ' ', style: Style = .text };

pub const max_cols = 256;
pub const max_rows = 100;

/// The drawn frame is at most this big and centered in a larger terminal.
pub const frame_cols = 80;
pub const frame_rows = 25;
pub const min_rows = 24;

pub const Screen = struct {
    cells: [max_rows][max_cols]Cell = undefined,
    cols: u16 = 80,
    rows: u16 = 25,
    /// top-left of the 80x25 frame inside the terminal
    ox: u16 = 0,
    oy: u16 = 0,
    /// frame height actually used (24 or 25)
    h: u16 = 25,

    pub fn begin(self: *Screen, size: sys.Size) void {
        self.cols = @min(size.cols, max_cols);
        self.rows = @min(size.rows, max_rows);
        self.h = @min(self.rows, frame_rows);
        self.ox = if (self.cols > frame_cols) (self.cols - frame_cols) / 2 else 0;
        self.oy = if (self.rows > frame_rows) (self.rows - frame_rows) / 2 else 0;
        for (self.cells[0..self.rows]) |*row| @memset(row[0..self.cols], Cell{});
    }

    pub fn fits(self: *const Screen) bool {
        return self.cols >= frame_cols and self.rows >= min_rows;
    }

    /// Writes ASCII/UTF-8 text at frame coordinates, clipped to `max_w`
    /// cells and the frame. Returns the cells used.
    pub fn text(self: *Screen, x: u16, y: u16, s: []const u8, style: Style, max_w: u16) u16 {
        if (y >= self.h) return 0;
        const ay = y + self.oy;
        var col = x;
        var used: u16 = 0;
        var i: usize = 0;
        while (i < s.len) {
            if (used >= max_w or col >= frame_cols) break;
            var cp: u21 = s[i];
            var n: usize = 1;
            if (s[i] >= 0x80) {
                n = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
                cp = if (i + n <= s.len) std.unicode.utf8Decode(s[i .. i + n]) catch '?' else '?';
                if (cp == '?') n = @max(1, @min(n, s.len - i));
                if (!consoleSafe(cp)) cp = '?';
            } else if (cp < 0x20 or cp == 0x7f) cp = '?';
            i += n;
            const ax = col + self.ox;
            if (ax < self.cols and ay < self.rows) self.cells[ay][ax] = .{ .ch = cp, .style = style };
            col += 1;
            used += 1;
        }
        return used;
    }

    pub fn fill(self: *Screen, x: u16, y: u16, w: u16, ch: u21, style: Style) void {
        var i: u16 = 0;
        while (i < w) : (i += 1) {
            const ax = x + i + self.ox;
            const ay = y + self.oy;
            if (x + i < frame_cols and y < self.h and ax < self.cols and ay < self.rows)
                self.cells[ay][ax] = .{ .ch = ch, .style = style };
        }
    }

    pub fn fmt(self: *Screen, x: u16, y: u16, style: Style, max_w: u16, comptime f: []const u8, args: anytype) u16 {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, f, args) catch buf[0..];
        return self.text(x, y, s, style, max_w);
    }

    /// A box-drawing frame around (x,y,w,h), inside cleared.
    pub fn box(self: *Screen, x: u16, y: u16, w: u16, h: u16, style: Style) void {
        self.fill(x, y, w, 0x2500, style);
        self.fill(x, y + h - 1, w, 0x2500, style);
        var r: u16 = 1;
        while (r + 1 < h) : (r += 1) {
            self.fill(x, y + r, 1, 0x2502, style);
            self.fill(x + 1, y + r, w - 2, ' ', .text);
            self.fill(x + w - 1, y + r, 1, 0x2502, style);
        }
        self.fill(x, y, 1, 0x250c, style);
        self.fill(x + w - 1, y, 1, 0x2510, style);
        self.fill(x, y + h - 1, 1, 0x2514, style);
        self.fill(x + w - 1, y + h - 1, 1, 0x2518, style);
    }

    /// Paints the whole terminal in one write.
    pub fn flush(self: *const Screen) void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(std.heap.page_allocator);
        const a = std.heap.page_allocator;
        out.appendSlice(a, "\x1b[H") catch return;
        var last: ?Style = null;
        for (self.cells[0..self.rows], 0..) |row, y| {
            if (y > 0) out.appendSlice(a, "\r\n") catch return;
            for (row[0..self.cols]) |c| {
                if (last != c.style) {
                    out.appendSlice(a, sgr(c.style)) catch return;
                    last = c.style;
                }
                var enc: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(c.ch, &enc) catch 1;
                if (n == 1 and c.ch > 0x7f) enc[0] = '?';
                out.appendSlice(a, enc[0..n]) catch return;
            }
        }
        out.appendSlice(a, "\x1b[0m") catch return;
        sys.writeAll(1, out.items);
    }
};

/// Entering and leaving the full-screen UI. Autowrap off so the last cell
/// does not scroll; cursor hidden, the UI draws its own.
pub const enter_seq = "\x1b[?1049h\x1b[?7l\x1b[?25l\x1b[0;37;40m\x1b[2J\x1b[H";
pub const leave_seq = "\x1b[0m\x1b[2J\x1b[H\x1b[?25h\x1b[?7h\x1b[?1049l";

/// Layout of the frame, in frame cells.
pub const rail_x = 2;
pub const rail_w = 14;
pub const sep_x = 17;
pub const cx = 20;
pub const cw = 58;
pub const top = 2;

pub fn progressBar(s: *Screen, x: u16, y: u16, w: u16, num: u32, den: u32) void {
    const filled: u16 = if (den == 0) 0 else @intCast(@min(@as(u64, w), @as(u64, w) * num / den));
    s.fill(x, y, filled, 0x2550, .accent);
    s.fill(x + filled, y, w - filled, 0x2500, .dim);
}
