//! app.zig - the installer's state, the page flow, the shared chrome and
//! the event loop. Pages draw and take keys in pages.zig and finish.zig.

const std = @import("std");
const sys = @import("sys.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const str = @import("strings.zig");
const system = @import("system.zig");
const disks = @import("disks.zig");
const progress = @import("progress.zig");
const pages = @import("pages.zig");
const finish = @import("finish.zig");

pub const Page = enum { welcome, network, keyboard, timezone, disk, encryption, account, review, install, done };

pub const Net = enum { checking, online, offline };
pub const Inst = enum { running, failed, finished };
pub const Pending = enum { none, check_network, nmtui, shell, start_engine, reboot };

pub const App = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    opts: system.Options,
    screen: *ui.Screen,

    page: Page = .welcome,
    pending: Pending = .none,
    quit_ask: bool = false,
    exit_code: ?u8 = null,
    /// one line under the page body: what went wrong, what to do
    msg: ?[]const u8 = null,
    /// where a page wants `msg`, next to what it is about; set while drawing
    msg_y: ?u16 = null,

    net: Net = .checking,
    net_choice: usize = 0,

    kb: input.Picker = .{},
    tz: input.Picker = .{},

    disk_list: []const disks.Disk = &.{},
    disk_ok: bool = true,
    disk_loaded: bool = false,
    disk_cursor: usize = 0,

    encrypt: bool = false,
    enc_focus: usize = 0,
    enc_pass: input.Field = .{ .secret = true },
    enc_again: input.Field = .{ .secret = true },

    acct_focus: usize = 0,
    acct: [5]input.Field = .{ .{}, .{}, .{ .secret = true }, .{ .secret = true }, .{} },
    acct_err: [5]?[]const u8 = @splat(null),
    user_edited: bool = false,

    confirm: input.Field = .{ .width = 10 },

    inst: Inst = .running,
    child: ?sys.Child = null,
    child_open: bool = false,
    splitter: progress.LineSplitter = .{},
    tail: progress.Tail = .{},
    step_n: u32 = 0,
    step_total: u32 = 0,
    step_label: [128]u8 = undefined,
    step_label_len: usize = 0,
    fail_reason: [160]u8 = undefined,
    fail_len: usize = 0,
    started_ms: i64 = 0,
    stop_ask: bool = false,
    inst_choice: usize = 0,
    answers_path: [:0]const u8 = "",

    done_choice: usize = 0,

    pub fn go(self: *App, p: Page) void {
        self.page = p;
        self.msg = null;
        switch (p) {
            .network => if (self.net != .online) {
                self.net = .checking;
                self.pending = .check_network;
            },
            .disk => if (!self.disk_loaded) self.loadDisks(),
            .review => self.confirm.clear(),
            else => {},
        }
    }

    pub fn next(self: *App) void {
        if (self.page != .done) self.go(@enumFromInt(@intFromEnum(self.page) + 1));
    }

    pub fn back(self: *App) void {
        const i = @intFromEnum(self.page);
        if (i > 0) self.go(@enumFromInt(i - 1));
    }

    pub fn loadDisks(self: *App) void {
        const p = system.probeDisks(self.arena, self.opts);
        self.disk_list = p.list;
        self.disk_ok = p.ok;
        self.disk_loaded = true;
        self.disk_cursor = 0;
        for (p.list, 0..) |d, i| if (!d.tooSmall()) {
            self.disk_cursor = i;
            break;
        };
    }

    pub fn wipeSecrets(self: *App) void {
        self.enc_pass.clear();
        self.enc_again.clear();
        for (&self.acct) |*f| f.clear();
    }
};

// ---- chrome ----

pub const Hint = struct { key: []const u8, what: []const u8 };

fn railIndex(p: Page) usize {
    return @min(@intFromEnum(p), str.steps.len);
}

fn drawChrome(app: *App) void {
    const s = app.screen;
    s.fill(0, 0, ui.frame_cols, ' ', .header);
    _ = s.text(2, 0, str.brand, .header, 20);
    _ = s.text(2 + str.brand.len + 1, 0, str.title, .header, 20);
    if (app.opts.demo) {
        const w: u16 = str.demo_badge.len;
        _ = s.text(ui.frame_cols - 2 - w, 0, str.demo_badge, .header, w);
    }
    const cur = railIndex(app.page);
    for (str.steps, 0..) |name, i| {
        const y: u16 = @intCast(ui.top + i);
        if (i < cur or app.page == .done) {
            _ = s.text(ui.rail_x, y, "+", .ok, 1);
            _ = s.text(ui.rail_x + 2, y, name, .text, ui.rail_w - 2);
        } else if (i == cur) {
            _ = s.text(ui.rail_x, y, ">", .accent, 1);
            _ = s.text(ui.rail_x + 2, y, name, .strong, ui.rail_w - 2);
        } else {
            _ = s.text(ui.rail_x + 2, y, name, .dim, ui.rail_w - 2);
        }
    }
    var y: u16 = ui.top;
    while (y < s.h - 2) : (y += 1) s.fill(ui.sep_x, y, 1, 0x2502, .dim);
}

pub fn footer(app: *App, hints: []const Hint) void {
    const s = app.screen;
    var x: u16 = 2;
    for (hints) |h| {
        x += s.text(x, s.h - 1, h.key, .strong, 20);
        x += 1;
        x += s.text(x, s.h - 1, h.what, .dim, 30);
        x += 3;
    }
}

/// Bottom row of the page body, for `app.msg`.
pub fn msgRow(app: *App) u16 {
    return app.screen.h - 3;
}

fn drawOverlay(app: *App, lines: []const []const u8, keys: []const u8) void {
    const s = app.screen;
    const w: u16 = 56;
    const h: u16 = @intCast(lines.len + 4);
    const x: u16 = (ui.frame_cols - w) / 2;
    const y: u16 = 8;
    s.box(x, y, w, h, .warn);
    for (lines, 0..) |l, i| _ = s.text(x + 2, @intCast(y + 1 + i), l, .strong, w - 4);
    _ = s.text(x + 2, y + h - 2, keys, .text, w - 4);
}

fn draw(app: *App) void {
    const s = app.screen;
    if (!s.fits()) {
        _ = s.text(0, 0, str.too_small, .warn, ui.frame_cols);
        return;
    }
    drawChrome(app);
    app.msg_y = null;
    switch (app.page) {
        .review, .install, .done => finish.draw(app),
        else => pages.draw(app),
    }
    if (app.msg) |m| {
        const y = app.msg_y orelse msgRow(app);
        _ = s.text(ui.cx, y, "!", .danger, 1);
        _ = s.text(ui.cx + 2, y, m, .danger, ui.cw - 2);
    }
    if (app.quit_ask) {
        const started = @intFromEnum(app.page) >= @intFromEnum(Page.install);
        drawOverlay(app, &.{if (started) str.quit_q_after else str.quit_q}, str.quit_keys);
    } else if (app.stop_ask) {
        drawOverlay(app, &.{ str.inst_stop_q, str.inst_stop_q2 }, str.inst_stop_keys);
    }
}

// ---- keys ----

fn isYes(key: input.Key) bool {
    return switch (key) {
        .char => |c| c == 'y' or c == 'Y',
        else => false,
    };
}

fn handleKey(app: *App, key: input.Key) !void {
    if (app.quit_ask) {
        app.quit_ask = false;
        if (isYes(key)) app.exit_code = if (app.page == .done) 0 else 1;
        return;
    }
    if (app.stop_ask) {
        app.stop_ask = false;
        if (isYes(key)) finish.stopEngine(app);
        return;
    }
    if (key == .ctrl_c) {
        if (app.page == .install and app.inst == .running) app.stop_ask = true else app.quit_ask = true;
        return;
    }
    switch (app.page) {
        .review, .install, .done => try finish.handle(app, key),
        else => try pages.handle(app, key),
    }
}

// ---- leaving the UI for another program ----

var saved_tty: ?sys.Termios = null;

pub fn enterUi() void {
    saved_tty = sys.rawMode(0);
    sys.writeAll(1, ui.enter_seq);
}

pub fn leaveUi() void {
    sys.writeAll(1, ui.leave_seq);
    if (saved_tty) |t| sys.restoreMode(0, t);
}

/// Runs a program on the plain terminal and comes back.
pub fn runOutside(app: *App, argv: []const []const u8, note: ?[]const u8) u8 {
    leaveUi();
    if (note) |n| {
        sys.writeAll(1, n);
        sys.writeAll(1, "\n\n");
    }
    const code = sys.interactive(app.gpa, argv);
    enterUi();
    return code;
}

fn doPending(app: *App) void {
    const p = app.pending;
    app.pending = .none;
    switch (p) {
        .none => {},
        .check_network => app.net = if (system.online(app.gpa, app.opts.check_url)) .online else .offline,
        .nmtui => {
            _ = runOutside(app, &.{"nmtui"}, null);
            app.net = .checking;
            app.pending = .check_network;
        },
        .shell => _ = runOutside(app, system.shellArgv(app.arena), str.shell_note),
        .start_engine => finish.startEngine(app),
        .reboot => {
            if (system.reboot(app.gpa, app.opts)) app.exit_code = 0 else app.msg = str.done_reboot_failed;
        },
    }
}

/// The event loop. Returns the process exit code.
pub fn run(app: *App) !u8 {
    enterUi();
    defer leaveUi();
    var last_draw: i64 = 0;
    var dirty = true;
    while (app.exit_code == null) {
        const now = sys.nowMs();
        if (dirty or now - last_draw >= 1000) {
            app.screen.begin(sys.winSize(1));
            draw(app);
            app.screen.flush();
            last_draw = now;
            dirty = false;
        }
        if (app.pending != .none) {
            doPending(app);
            dirty = true;
            continue;
        }
        if (app.child) |c| {
            // Checked even while the pipe is open: a daemon the engine
            // started may hold it after the engine itself has exited.
            if (sys.tryWait(c.pid)) |code| {
                finish.drainEngine(app);
                finish.engineExited(app, code);
                dirty = true;
                continue;
            }
        }
        var fds: [2]i32 = .{ 0, -1 };
        var nfds: usize = 1;
        if (app.child != null and app.child_open) {
            fds[1] = app.child.?.out;
            nfds = 2;
        }
        const ready = sys.pollIn(fds[0..nfds], 250);
        if (ready & 2 != 0) {
            finish.readEngine(app);
            dirty = true;
        }
        if (ready & 1 != 0) {
            var buf: [256]u8 = undefined;
            const n = sys.read(0, &buf) catch 0;
            if (n == 0) return 1; // the terminal went away
            var i: usize = 0;
            while (i < n) {
                const d = input.decode(buf[i..n]);
                i += d.len;
                try handleKey(app, d.key);
                if (app.exit_code != null or app.pending != .none) break;
            }
            dirty = true;
        }
    }
    return app.exit_code.?;
}
