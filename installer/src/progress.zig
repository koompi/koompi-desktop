//! progress.zig - reading the engine's output: `@@koompi` progress lines and
//! the tail of the free-form log.

const std = @import("std");

pub const Event = union(enum) {
    step: struct { n: u32, total: u32, label: []const u8 },
    done,
    fail: []const u8,
    log: []const u8,
};

const prefix = "@@koompi ";

/// Classifies one line (no newline). A malformed `@@koompi` line is kept as
/// log text rather than dropped, so nothing the engine says is lost.
pub fn parseLine(line: []const u8) Event {
    if (!std.mem.startsWith(u8, line, prefix)) return .{ .log = line };
    const rest = std.mem.trim(u8, line[prefix.len..], " \t\r");
    if (std.mem.eql(u8, rest, "done")) return .done;
    if (std.mem.startsWith(u8, rest, "fail")) {
        const tail = rest["fail".len..];
        if (tail.len == 0) return .{ .fail = "" };
        if (tail[0] == ' ') return .{ .fail = std.mem.trim(u8, tail, " ") };
    }
    if (std.mem.startsWith(u8, rest, "step ")) {
        const body = std.mem.trimStart(u8, rest["step ".len..], " ");
        const sp = std.mem.indexOfScalar(u8, body, ' ') orelse body.len;
        const frac = body[0..sp];
        const slash = std.mem.indexOfScalar(u8, frac, '/') orelse return .{ .log = line };
        const n = std.fmt.parseInt(u32, frac[0..slash], 10) catch return .{ .log = line };
        const total = std.fmt.parseInt(u32, frac[slash + 1 ..], 10) catch return .{ .log = line };
        if (total == 0 or n == 0 or n > total) return .{ .log = line };
        return .{ .step = .{ .n = n, .total = total, .label = std.mem.trim(u8, body[sp..], " ") } };
    }
    return .{ .log = line };
}

/// Splits a byte stream into lines. `\r` also ends a line, so a progress
/// meter redrawn with carriage returns shows its latest state.
pub const LineSplitter = struct {
    buf: [1024]u8 = undefined,
    len: usize = 0,

    /// Calls `sink.line(line)` for every complete line in `bytes`.
    pub fn feed(self: *LineSplitter, bytes: []const u8, sink: anytype) void {
        for (bytes) |c| {
            if (c == '\n' or c == '\r') {
                if (self.len > 0) sink.line(self.buf[0..self.len]);
                self.len = 0;
            } else if (self.len < self.buf.len) {
                self.buf[self.len] = c;
                self.len += 1;
            }
        }
    }

    pub fn flush(self: *LineSplitter, sink: anytype) void {
        if (self.len > 0) sink.line(self.buf[0..self.len]);
        self.len = 0;
    }
};

/// The last `cap` log lines, with escape sequences and control bytes removed.
pub const Tail = struct {
    pub const cap = 10;
    lines: [cap][160]u8 = undefined,
    lens: [cap]usize = @splat(0),
    start: usize = 0,
    count: usize = 0,

    pub fn push(self: *Tail, raw: []const u8) void {
        var clean: [160]u8 = undefined;
        const n = stripControl(raw, &clean);
        if (n == 0) return;
        const slot = (self.start + self.count) % cap;
        @memcpy(self.lines[slot][0..n], clean[0..n]);
        self.lens[slot] = n;
        if (self.count < cap) self.count += 1 else self.start = (self.start + 1) % cap;
    }

    pub fn get(self: *const Tail, i: usize) []const u8 {
        const slot = (self.start + i) % cap;
        return self.lines[slot][0..self.lens[slot]];
    }

    pub fn clear(self: *Tail) void {
        self.count = 0;
        self.start = 0;
    }
};

/// Copies `raw` into `out` without ANSI CSI/OSC sequences and other control
/// bytes; tabs become a space. Returns the length written.
pub fn stripControl(raw: []const u8, out: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < raw.len and n < out.len) {
        const c = raw[i];
        if (c == 0x1b) {
            i += 1;
            if (i < raw.len and raw[i] == '[') {
                i += 1;
                while (i < raw.len and !(raw[i] >= 0x40 and raw[i] <= 0x7e)) i += 1;
                i += 1;
            } else if (i < raw.len and raw[i] == ']') {
                while (i < raw.len and raw[i] != 0x07 and raw[i] != 0x1b) i += 1;
                i += 1;
            } else i += 1;
            continue;
        }
        if (c == '\t') {
            out[n] = ' ';
            n += 1;
        } else if (c >= 0x20 and c != 0x7f) {
            out[n] = c;
            n += 1;
        }
        i += 1;
    }
    return std.mem.trimEnd(u8, out[0..n], " ").len;
}

const t = std.testing;

test "@@koompi step lines" {
    const e = parseLine("@@koompi step 2/4 Installing the base system");
    try t.expectEqual(@as(u32, 2), e.step.n);
    try t.expectEqual(@as(u32, 4), e.step.total);
    try t.expectEqualStrings("Installing the base system", e.step.label);
    const bare = parseLine("@@koompi step 1/3");
    try t.expectEqualStrings("", bare.step.label);
}

test "@@koompi done and fail" {
    try t.expect(parseLine("@@koompi done") == .done);
    try t.expect(parseLine("@@koompi done  \r") == .done);
    try t.expectEqualStrings("disk is busy", parseLine("@@koompi fail disk is busy").fail);
    try t.expectEqualStrings("", parseLine("@@koompi fail").fail);
}

test "malformed and ordinary lines stay log text" {
    const cases = [_][]const u8{
        "@@koompi step x/4 Bad",
        "@@koompi step 5/4 Past the end",
        "@@koompi step 0/4 Zero",
        "@@koompi step 2-4 No slash",
        "@@koompi failed to parse",
        "@@koompi",
        "@@koompix step 1/2 a",
        " @@koompi done",
        "Installing linux...",
        "",
    };
    for (cases) |c| try t.expect(parseLine(c) == .log);
}

test "line splitter and tail" {
    const Sink = struct {
        tail: Tail = .{},
        pub fn line(self: *@This(), l: []const u8) void {
            self.tail.push(l);
        }
    };
    var sink = Sink{};
    var sp = LineSplitter{};
    sp.feed("one\ntw", &sink);
    sp.feed("o\r\n\x1b[1;32mthree\x1b[0m\tx\n", &sink);
    sp.feed("tail", &sink);
    try t.expectEqual(@as(usize, 3), sink.tail.count);
    try t.expectEqualStrings("two", sink.tail.get(1));
    try t.expectEqualStrings("three x", sink.tail.get(2));
    sp.flush(&sink);
    try t.expectEqualStrings("tail", sink.tail.get(3));
    var i: usize = 0;
    while (i < 20) : (i += 1) sink.tail.push("x");
    try t.expectEqual(@as(usize, Tail.cap), sink.tail.count);
}
