//! finish.zig - review, install and done: the one destructive gate, the
//! engine run and its progress, and what to do after.

const std = @import("std");
const linux = std.os.linux;
const sys = @import("sys.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const str = @import("strings.zig");
const disks = @import("disks.zig");
const answers = @import("answers.zig");
const progress = @import("progress.zig");
const pages = @import("pages.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const Key = input.Key;

pub fn draw(app: *App) void {
    switch (app.page) {
        .review => drawReview(app),
        .install => drawInstall(app),
        .done => drawDone(app),
        else => {},
    }
}

pub fn handle(app: *App, key: Key) !void {
    switch (app.page) {
        .review => handleReview(app, key),
        .install => handleInstall(app, key),
        .done => handleDone(app, key),
        else => {},
    }
}

fn collect(app: *App) answers.Answers {
    const d = app.disk_list[app.disk_cursor];
    return .{
        .disk = d.path,
        .encrypt = app.encrypt,
        .encryption_password = if (app.encrypt) app.enc_pass.value() else "",
        .hostname = app.acct[4].value(),
        .full_name = app.acct[0].value(),
        .username = app.acct[1].value(),
        .password = app.acct[2].value(),
        .timezone = app.tz.current() orelse "Asia/Phnom_Penh",
        .keyboard = app.kb.current() orelse "us",
        .locale = "en_US.UTF-8",
    };
}

// ---- review ----

fn line(app: *App, y: u16, label: []const u8, value: []const u8, style: ui.Style) void {
    _ = app.screen.text(ui.cx, y, label, .dim, 12);
    _ = app.screen.text(ui.cx + 12, y, value, style, ui.cw - 12);
}

fn drawReview(app: *App) void {
    const s = app.screen;
    const a = collect(app);
    const d = app.disk_list[app.disk_cursor];
    _ = s.text(ui.cx, ui.top, str.rev_h, .strong, ui.cw);
    var y: u16 = ui.top + 2;
    var size_buf: [16]u8 = undefined;
    var buf: [96]u8 = undefined;
    line(app, y, str.rev_disk, std.fmt.bufPrint(&buf, "{s}  {s}  {s}", .{ d.path, disks.humanSize(&size_buf, d.size), d.model }) catch d.path, .strong);
    y += 1;
    _ = s.text(ui.cx + 12, y, str.rev_erase, .danger, ui.cw - 12);
    y += 2;
    line(app, y, str.rev_enc, if (a.encrypt) str.enc_on else str.enc_off, .text);
    y += 1;
    var ubuf: [128]u8 = undefined;
    const who = if (a.full_name.len > 0)
        std.fmt.bufPrint(&ubuf, "{s} ({s})", .{ a.full_name, a.username }) catch a.username
    else
        a.username;
    line(app, y, str.rev_user, who, .text);
    y += 1;
    line(app, y, str.rev_host, a.hostname, .text);
    y += 1;
    line(app, y, str.rev_kb, a.keyboard, .text);
    y += 1;
    line(app, y, str.rev_tz, a.timezone, .text);
    y += 2;
    _ = s.text(ui.cx, y, str.rev_time1, .text, ui.cw);
    _ = s.text(ui.cx, y + 1, str.rev_time2, .text, ui.cw);
    y += 3;
    _ = s.text(ui.cx, y, str.rev_confirm, .warn, ui.cw);
    const fx = ui.cx + @as(u16, str.rev_confirm.len) + 1;
    s.fill(fx, y, app.confirm.width, ' ', .field_focus);
    _ = s.text(fx, y, app.confirm.value(), .field_focus, app.confirm.width - 1);
    s.fill(fx + @as(u16, @intCast(@min(app.confirm.len, app.confirm.width - 1))), y, 1, '_', .field_focus);
    app.msg_y = y + 1;
    app_mod.footer(app, &.{
        .{ .key = str.k_enter, .what = "install" },
        .{ .key = str.k_esc, .what = "change something" },
        .{ .key = str.k_quit, .what = str.f_quit },
    });
}

fn handleReview(app: *App, key: Key) void {
    switch (key) {
        .esc => app.back(),
        .enter => {
            const v = std.mem.trim(u8, app.confirm.value(), " ");
            if (!std.mem.eql(u8, v, str.rev_confirm_word)) {
                app.msg = str.rev_confirm_wrong;
                return;
            }
            app.go(.install);
            app.pending = .start_engine;
        },
        else => if (app.confirm.edit(key)) {
            app.msg = null;
        },
    }
}

// ---- install ----

fn setFail(app: *App, comptime f: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&app.fail_reason, f, args) catch app.fail_reason[0..];
    app.fail_len = s.len;
    app.inst = .failed;
    app.inst_choice = 0;
}

pub fn startEngine(app: *App) void {
    app.inst = .running;
    app.tail.clear();
    app.step_n = 0;
    app.step_total = 0;
    app.step_label_len = 0;
    app.fail_len = 0;
    app.started_ms = sys.nowMs();

    const engine_z = sys.dupeZ(app.arena, app.opts.engine) catch return setFail(app, "out of memory", .{});
    if (!sys.exists(engine_z)) return setFail(app, "{s} {s}", .{ str.inst_no_engine, app.opts.engine });

    const dir_z = sys.dupeZ(app.arena, app.opts.answers_dir) catch return setFail(app, "out of memory", .{});
    app.answers_path = std.fmt.allocPrintSentinel(app.arena, "{s}/answers.json", .{app.opts.answers_dir}, 0) catch
        return setFail(app, "out of memory", .{});
    const json = answers.toJson(app.gpa, collect(app)) catch return setFail(app, "out of memory", .{});
    defer {
        std.crypto.secureZero(u8, json);
        app.gpa.free(json);
    }
    sys.mkdirMode(dir_z, 0o700) catch return setFail(app, "{s} {s}", .{ str.inst_answers_failed, app.opts.answers_dir });
    sys.writeSecretFile(app.answers_path, json, 0o600) catch
        return setFail(app, "{s} {s}", .{ str.inst_answers_failed, app.answers_path });

    const child = sys.spawnPiped(app.gpa, &.{ app.opts.engine, "--answers", app.answers_path }) catch {
        sys.unlink(app.answers_path);
        return setFail(app, "{s} {s}", .{ str.inst_no_engine, app.opts.engine });
    };
    app.child = child;
    app.child_open = true;
    app.splitter = .{};
}

const Sink = struct {
    app: *App,
    pub fn line(self: Sink, l: []const u8) void {
        const app = self.app;
        switch (progress.parseLine(l)) {
            .step => |st| {
                app.step_n = st.n;
                app.step_total = st.total;
                const n = @min(st.label.len, app.step_label.len);
                @memcpy(app.step_label[0..n], st.label[0..n]);
                app.step_label_len = n;
            },
            .done => app.step_n = app.step_total,
            .fail => |r| {
                app.fail_len = progress.stripControl(if (r.len > 0) r else "(no reason given)", &app.fail_reason);
            },
            .log => |text| app.tail.push(text),
        }
    }
};

pub fn readEngine(app: *App) void {
    const c = app.child orelse return;
    var buf: [4096]u8 = undefined;
    const n = sys.read(c.out, &buf) catch 0;
    if (n == 0) {
        app.splitter.flush(Sink{ .app = app });
        sys.close(c.out);
        app.child_open = false;
        return;
    }
    app.splitter.feed(buf[0..n], Sink{ .app = app });
}

/// Reads what is already in the pipe, then closes it.
pub fn drainEngine(app: *App) void {
    var guard: usize = 0;
    while (app.child_open and guard < 256) : (guard += 1) {
        if (sys.pollIn(&.{app.child.?.out}, 0) == 0) break;
        readEngine(app);
    }
    if (app.child_open) {
        app.splitter.flush(Sink{ .app = app });
        sys.close(app.child.?.out);
        app.child_open = false;
    }
}

pub fn engineExited(app: *App, code: u8) void {
    app.child = null;
    if (app.answers_path.len > 0) sys.unlink(app.answers_path);
    if (code == 0 and app.fail_len == 0) {
        app.inst = .finished;
        app.wipeSecrets();
        app.go(.done);
        return;
    }
    if (app.fail_len == 0) setFail(app, "{s} {d}.", .{ str.inst_exit_code, code }) else {
        app.inst = .failed;
        app.inst_choice = 0;
    }
}

pub fn stopEngine(app: *App) void {
    const c = app.child orelse return;
    if (app.inst != .running) return;
    _ = linux.kill(-c.pid, .TERM);
    setFail(app, "{s}", .{str.inst_stopped});
    app.inst = .running; // until it has exited; engineExited settles it
}

fn drawInstall(app: *App) void {
    const s = app.screen;
    var y: u16 = ui.top;
    if (app.inst == .failed) return drawFailed(app);
    _ = s.text(ui.cx, y, str.inst_h, .strong, ui.cw);
    y += 2;
    if (app.step_total == 0) {
        _ = s.text(ui.cx, y, str.inst_starting, .accent, ui.cw);
    } else {
        const w = s.fmt(ui.cx, y, .accent, ui.cw, "{s} {d} {s} {d}", .{ str.inst_step, app.step_n, str.inst_of, app.step_total });
        _ = s.text(ui.cx + w + 3, y, app.step_label[0..app.step_label_len], .strong, ui.cw - w - 3);
    }
    y += 1;
    // a running step counts as half done, so the bar moves when it starts
    const den = app.step_total * 2;
    const num = if (app.step_n == 0) 0 else (app.step_n * 2 - 1);
    ui.progressBar(s, ui.cx, y, ui.cw - 8, num, den);
    const secs = @divTrunc(sys.nowMs() - app.started_ms, 1000);
    _ = s.fmt(ui.cx + ui.cw - 6, y, .dim, 6, "{d:0>2}:{d:0>2}", .{ @as(u64, @intCast(@divTrunc(secs, 60))), @as(u64, @intCast(@mod(secs, 60))) });
    y += 1;
    _ = s.text(ui.cx, y, str.inst_keep_on, .dim, ui.cw);
    y += 2;
    var i: usize = 0;
    while (i < app.tail.count) : (i += 1) _ = s.text(ui.cx, @intCast(y + i), app.tail.get(i), .dim, ui.cw);
    app_mod.footer(app, &.{.{ .key = str.k_quit, .what = "stop" }});
}

fn drawFailed(app: *App) void {
    const s = app.screen;
    var y: u16 = ui.top;
    _ = s.text(ui.cx, y, str.inst_failed_h, .danger, ui.cw);
    y += 2;
    _ = s.text(ui.cx, y, "!", .danger, 1);
    _ = s.text(ui.cx + 2, y, app.fail_reason[0..app.fail_len], .strong, ui.cw - 2);
    y += 1;
    _ = s.text(ui.cx, y, str.inst_log_at, .dim, 10);
    _ = s.text(ui.cx + 10, y, str.inst_log_path, .text, ui.cw - 10);
    y += 2;
    const opts = [_][]const u8{ str.inst_retry, str.inst_shell };
    for (opts, 0..) |o, i| pages.row(app, @intCast(y + i), o, i == app.inst_choice, .text);
    y += 3;
    var i: usize = 0;
    while (i < app.tail.count and y + i < app_mod.msgRow(app)) : (i += 1)
        _ = s.text(ui.cx, @intCast(y + i), app.tail.get(i), .dim, ui.cw);
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_move },
        .{ .key = str.k_enter, .what = str.f_choose },
        .{ .key = str.k_esc, .what = "change answers" },
        .{ .key = str.k_quit, .what = str.f_quit },
    });
}

fn handleInstall(app: *App, key: Key) void {
    if (app.inst != .failed) return;
    switch (key) {
        .up => app.inst_choice = 0,
        .down, .tab => app.inst_choice = 1,
        .esc => app.go(.review),
        .enter => {
            if (app.inst_choice == 0) {
                app.pending = .start_engine;
                app.inst = .running;
            } else app.pending = .shell;
        },
        else => {},
    }
}

// ---- done ----

fn drawDone(app: *App) void {
    const s = app.screen;
    _ = s.text(ui.cx, ui.top, "+", .ok, 1);
    _ = s.text(ui.cx + 2, ui.top, str.done_h, .ok, ui.cw);
    for (str.done_lines, 0..) |l, i| {
        _ = s.text(ui.cx, @intCast(ui.top + 2 + i), l, if (i < 2) .strong else .text, ui.cw);
    }
    const y: u16 = ui.top + 9;
    const opts = [_][]const u8{ str.done_reboot, str.done_stay };
    for (opts, 0..) |o, i| pages.row(app, @intCast(y + i), o, i == app.done_choice, .text);
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_move },
        .{ .key = str.k_enter, .what = str.f_choose },
    });
}

fn handleDone(app: *App, key: Key) void {
    switch (key) {
        .up => app.done_choice = 0,
        .down, .tab => app.done_choice = 1,
        .enter => {
            if (app.done_choice == 0) app.pending = .reboot else app.exit_code = 0;
        },
        else => {},
    }
}
