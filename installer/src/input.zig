//! input.zig - keys from a raw terminal, the text field, and the
//! searchable list used for keyboard layouts and time zones.

const std = @import("std");

pub const Key = union(enum) {
    char: u8,
    enter,
    backspace,
    delete,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    esc,
    ctrl_c,
    ctrl_u,
    unknown,
};

/// Decodes one key from the front of `buf`; returns it and the bytes used.
/// A lone ESC is Esc; an unknown sequence is swallowed whole.
pub fn decode(buf: []const u8) struct { key: Key, len: usize } {
    const c = buf[0];
    switch (c) {
        '\r', '\n' => return .{ .key = .enter, .len = 1 },
        0x7f, 0x08 => return .{ .key = .backspace, .len = 1 },
        '\t' => return .{ .key = .tab, .len = 1 },
        0x03 => return .{ .key = .ctrl_c, .len = 1 },
        0x15 => return .{ .key = .ctrl_u, .len = 1 },
        0x1b => {},
        0x20...0x7e => return .{ .key = .{ .char = c }, .len = 1 },
        else => return .{ .key = .unknown, .len = 1 },
    }
    if (buf.len == 1) return .{ .key = .esc, .len = 1 };
    if (buf[1] != '[' and buf[1] != 'O') return .{ .key = .esc, .len = 1 };
    // CSI or SS3: parameters then one final byte 0x40-0x7e.
    var i: usize = 2;
    while (i < buf.len and !(buf[i] >= 0x40 and buf[i] <= 0x7e)) i += 1;
    if (i >= buf.len) return .{ .key = .unknown, .len = buf.len };
    const params = buf[2..i];
    const key: Key = switch (buf[i]) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        '~' => tilde(params),
        else => .unknown,
    };
    return .{ .key = key, .len = i + 1 };
}

fn tilde(params: []const u8) Key {
    const n = std.fmt.parseInt(u8, params, 10) catch return .unknown;
    return switch (n) {
        1, 7 => .home,
        4, 8 => .end,
        3 => .delete,
        5 => .page_up,
        6 => .page_down,
        else => .unknown,
    };
}

/// One line of ASCII text, edited at the end. Secrets are drawn masked and
/// wiped when cleared.
pub const Field = struct {
    buf: [64]u8 = undefined,
    len: usize = 0,
    secret: bool = false,
    /// how many cells the field shows
    width: u16 = 30,

    pub fn value(self: *const Field) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *Field, s: []const u8) void {
        const n = @min(s.len, self.buf.len);
        @memcpy(self.buf[0..n], s[0..n]);
        self.len = n;
    }

    pub fn clear(self: *Field) void {
        std.crypto.secureZero(u8, &self.buf);
        self.len = 0;
    }

    /// Applies an editing key. Returns true when the key was used.
    pub fn edit(self: *Field, key: Key) bool {
        switch (key) {
            .char => |c| {
                if (self.len < self.buf.len) {
                    self.buf[self.len] = c;
                    self.len += 1;
                }
                return true;
            },
            .backspace => {
                if (self.len > 0) self.len -= 1;
                self.buf[self.len] = 0;
                return true;
            },
            .ctrl_u => {
                self.clear();
                return true;
            },
            else => return false,
        }
    }
};

/// A long list narrowed by a search typed as you go.
pub const Picker = struct {
    items: []const []const u8 = &.{},
    search: Field = .{ .width = 30 },
    /// indexes into items that match the search
    shown: std.ArrayList(u32) = .empty,
    cursor: usize = 0,
    top: usize = 0,
    /// the first draw puts the preselected item mid-list, not at the edge
    center: bool = true,

    pub fn init(self: *Picker, gpa: std.mem.Allocator, items: []const []const u8, preselect: []const u8) !void {
        self.items = items;
        try self.refilter(gpa);
        self.select(preselect);
    }

    pub fn deinit(self: *Picker, gpa: std.mem.Allocator) void {
        self.shown.deinit(gpa);
    }

    pub fn select(self: *Picker, name: []const u8) void {
        for (self.shown.items, 0..) |idx, i| {
            if (std.mem.eql(u8, self.items[idx], name)) {
                self.cursor = i;
                return;
            }
        }
    }

    pub fn current(self: *const Picker) ?[]const u8 {
        if (self.cursor >= self.shown.items.len) return null;
        return self.items[self.shown.items[self.cursor]];
    }

    fn refilter(self: *Picker, gpa: std.mem.Allocator) !void {
        const keep = self.current();
        self.shown.clearRetainingCapacity();
        const q = self.search.value();
        for (self.items, 0..) |item, i| {
            if (q.len == 0 or containsFold(item, q)) try self.shown.append(gpa, @intCast(i));
        }
        self.cursor = 0;
        self.top = 0;
        self.center = true;
        if (keep) |k| self.select(k);
    }

    /// Moves or searches. `rows` is the visible height, for paging and
    /// keeping the cursor on screen. Returns true when the key was used.
    pub fn handle(self: *Picker, gpa: std.mem.Allocator, key: Key, rows: usize) !bool {
        const n = self.shown.items.len;
        switch (key) {
            .up => self.cursor -|= 1,
            .down => if (self.cursor + 1 < n) {
                self.cursor += 1;
            },
            .page_up => self.cursor -|= rows,
            .page_down => self.cursor = @min(self.cursor + rows, n -| 1),
            .home => self.cursor = 0,
            .end => self.cursor = n -| 1,
            .char, .backspace, .ctrl_u => {
                if (!self.search.edit(key)) return false;
                try self.refilter(gpa);
            },
            else => return false,
        }
        self.scroll(rows);
        return true;
    }

    pub fn scroll(self: *Picker, rows: usize) void {
        if (rows == 0) return;
        if (self.center) {
            self.center = false;
            self.top = self.cursor -| rows / 2;
        }
        if (self.cursor < self.top) self.top = self.cursor;
        if (self.cursor >= self.top + rows) self.top = self.cursor + 1 - rows;
    }
};

pub fn containsFold(hay: []const u8, needle: []const u8) bool {
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

const t = std.testing;

test "key decoding: plain keys and console/xterm sequences" {
    try t.expect(decode("\r").key == .enter);
    try t.expect(decode("\x7f").key == .backspace);
    try t.expect(decode("\x03").key == .ctrl_c);
    try t.expectEqual(@as(u8, 'a'), decode("ab").key.char);
    try t.expect(decode("\x1b").key == .esc);
    try t.expect(decode("\x1b[A").key == .up);
    try t.expect(decode("\x1bOB").key == .down);
    try t.expect(decode("\x1b[1~").key == .home);
    try t.expect(decode("\x1b[4~").key == .end);
    try t.expect(decode("\x1b[3~").key == .delete);
    try t.expect(decode("\x1b[6~").key == .page_down);
    const r = decode("\x1b[1;5Cx");
    try t.expect(r.key == .right);
    try t.expectEqual(@as(usize, 6), r.len);
    try t.expect(decode("\x1b[[A").key == .unknown); // console F1 is ESC [ [ A
}

test "field editing" {
    var f = Field{};
    _ = f.edit(.{ .char = 'h' });
    _ = f.edit(.{ .char = 'i' });
    try t.expectEqualStrings("hi", f.value());
    _ = f.edit(.backspace);
    try t.expectEqualStrings("h", f.value());
    _ = f.edit(.ctrl_u);
    try t.expectEqualStrings("", f.value());
    try t.expect(!f.edit(.up));
}

test "picker search keeps the selection when it still matches" {
    const items = [_][]const u8{ "Asia/Bangkok", "Asia/Phnom_Penh", "Europe/Paris", "UTC" };
    var p = Picker{};
    defer p.deinit(t.allocator);
    try p.init(t.allocator, &items, "Asia/Phnom_Penh");
    try t.expectEqualStrings("Asia/Phnom_Penh", p.current().?);
    for ("pen") |c| _ = try p.handle(t.allocator, .{ .char = c }, 5);
    try t.expectEqual(@as(usize, 1), p.shown.items.len);
    try t.expectEqualStrings("Asia/Phnom_Penh", p.current().?);
    _ = try p.handle(t.allocator, .ctrl_u, 5);
    for ("zzz") |c| _ = try p.handle(t.allocator, .{ .char = c }, 5);
    try t.expect(p.current() == null);
}
