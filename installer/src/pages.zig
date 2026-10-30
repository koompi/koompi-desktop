//! pages.zig - the question pages: welcome, network, keyboard, time zone,
//! disk, encryption, account.

const std = @import("std");
const ui = @import("ui.zig");
const input = @import("input.zig");
const str = @import("strings.zig");
const system = @import("system.zig");
const disks = @import("disks.zig");
const answers = @import("answers.zig");
const app_mod = @import("app.zig");
const App = app_mod.App;
const Hint = app_mod.Hint;
const Key = input.Key;

const nav_hints = [_]Hint{
    .{ .key = str.k_enter, .what = str.f_continue },
    .{ .key = str.k_esc, .what = str.f_back },
    .{ .key = str.k_quit, .what = str.f_quit },
};

pub fn draw(app: *App) void {
    switch (app.page) {
        .welcome => drawWelcome(app),
        .network => drawNetwork(app),
        .keyboard => drawPicker(app, &app.kb, str.kb_h),
        .timezone => drawPicker(app, &app.tz, str.tz_h),
        .disk => drawDisk(app),
        .encryption => drawEncryption(app),
        .account => drawAccount(app),
        else => {},
    }
}

pub fn handle(app: *App, key: Key) !void {
    if (key == .esc) {
        app.back();
        return;
    }
    switch (app.page) {
        .welcome => if (key == .enter) app.next(),
        .network => handleNetwork(app, key),
        .keyboard => try handlePicker(app, &app.kb, key),
        .timezone => try handlePicker(app, &app.tz, key),
        .disk => handleDisk(app, key),
        .encryption => handleEncryption(app, key),
        .account => handleAccount(app, key),
        else => {},
    }
}

fn heading(app: *App, s: []const u8) void {
    _ = app.screen.text(ui.cx, ui.top, s, .strong, ui.cw);
}

/// A list row; the selected one is a full-width bar with a > mark.
pub fn row(app: *App, y: u16, label: []const u8, selected: bool, style: ui.Style) void {
    const s = app.screen;
    if (selected) {
        s.fill(ui.cx, y, ui.cw, ' ', .select);
        _ = s.text(ui.cx, y, ">", .select, 1);
        _ = s.text(ui.cx + 2, y, label, .select, ui.cw - 3);
    } else {
        _ = s.text(ui.cx + 2, y, label, style, ui.cw - 3);
    }
}

/// `label  [value___]`; the focused field is a blue bar with a cursor.
pub fn field(app: *App, y: u16, label: []const u8, f: *const input.Field, focused: bool) void {
    const s = app.screen;
    const fx: u16 = ui.cx + 15;
    _ = s.text(ui.cx, y, label, if (focused) .strong else .text, 14);
    const style: ui.Style = if (focused) .field_focus else .field;
    if (focused) s.fill(fx, y, f.width, ' ', style) else s.fill(fx, y, f.width, '_', .dim);
    const v = f.value();
    const shown = @min(v.len, f.width - 1);
    var i: u16 = 0;
    while (i < shown) : (i += 1) {
        const c: u8 = if (f.secret) '*' else v[v.len - shown + i];
        s.fill(fx + i, y, 1, c, style);
    }
    if (focused) s.fill(fx + i, y, 1, '_', style);
}

fn fieldError(app: *App, y: u16, err: ?[]const u8) void {
    const e = err orelse return;
    _ = app.screen.text(ui.cx + 15, y, "!", .danger, 1);
    _ = app.screen.text(ui.cx + 17, y, e, .danger, ui.cw - 17);
}

// ---- welcome ----

fn drawWelcome(app: *App) void {
    const s = app.screen;
    heading(app, str.welcome_h);
    for (str.welcome_lines, 0..) |l, i| {
        const style: ui.Style = if (i >= 3) .warn else .text;
        _ = s.text(ui.cx, @intCast(ui.top + 2 + i), l, style, ui.cw);
    }
    _ = s.text(ui.cx, ui.top + 9, str.welcome_needs, .dim, ui.cw);
    app_mod.footer(app, &.{ .{ .key = str.k_enter, .what = "start" }, .{ .key = str.k_quit, .what = str.f_quit } });
}

// ---- network ----

fn drawNetwork(app: *App) void {
    const s = app.screen;
    heading(app, str.net_h);
    const y = ui.top + 2;
    switch (app.net) {
        .checking => _ = s.text(ui.cx, y, str.net_checking, .accent, ui.cw),
        .online => {
            _ = s.text(ui.cx, y, "+", .ok, 1);
            _ = s.text(ui.cx + 2, y, str.net_online, .ok, ui.cw);
        },
        .offline => {
            _ = s.text(ui.cx, y, "!", .danger, 1);
            _ = s.text(ui.cx + 2, y, str.net_offline, .danger, ui.cw);
            row(app, y + 2, str.net_connect, app.net_choice == 0, .text);
            row(app, y + 3, str.net_retry, app.net_choice == 1, .text);
        },
    }
    _ = s.text(ui.cx, y + 6, str.net_why, .dim, ui.cw);
    if (app.net == .offline) {
        app_mod.footer(app, &.{
            .{ .key = str.k_arrows, .what = str.f_move },
            .{ .key = str.k_enter, .what = str.f_choose },
            .{ .key = str.k_esc, .what = str.f_back },
            .{ .key = str.k_quit, .what = str.f_quit },
        });
    } else app_mod.footer(app, &nav_hints);
}

fn handleNetwork(app: *App, key: Key) void {
    switch (app.net) {
        .checking => {},
        .online => if (key == .enter) app.next(),
        .offline => switch (key) {
            .up => app.net_choice = 0,
            .down, .tab => app.net_choice = 1,
            .enter => {
                app.net = .checking;
                app.pending = if (app.net_choice == 0) .nmtui else .check_network;
            },
            else => {},
        },
    }
}

// ---- keyboard and time zone ----

fn pickerRows(app: *App) usize {
    return app.screen.h - 3 - (ui.top + 4);
}

fn drawPicker(app: *App, p: *input.Picker, title: []const u8) void {
    const s = app.screen;
    heading(app, title);
    const sy = ui.top + 2;
    const sf = input.Field{ .buf = p.search.buf, .len = p.search.len, .width = 24 };
    _ = s.text(ui.cx, sy, str.search, .text, 10);
    field(app, sy, "", &sf, true);
    _ = s.fmt(ui.cx + 41, sy, .dim, 17, "{d} of {d}", .{ p.shown.items.len, p.items.len });
    const rows = pickerRows(app);
    p.scroll(rows);
    if (p.shown.items.len == 0) _ = s.text(ui.cx + 2, sy + 2, str.no_match, .dim, ui.cw);
    var i: usize = 0;
    while (i < rows and p.top + i < p.shown.items.len) : (i += 1) {
        const idx = p.top + i;
        row(app, @intCast(sy + 2 + i), p.items[p.shown.items[idx]], idx == p.cursor, .text);
    }
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_move },
        .{ .key = "a-z", .what = str.f_type },
        .{ .key = str.k_enter, .what = str.f_choose },
        .{ .key = str.k_esc, .what = str.f_back },
    });
}

fn handlePicker(app: *App, p: *input.Picker, key: Key) !void {
    if (key == .enter) {
        const choice = p.current() orelse return;
        if (p == &app.kb) system.loadkeys(app.gpa, app.opts, choice);
        app.next();
        return;
    }
    _ = try p.handle(app.gpa, key, pickerRows(app));
}

// ---- disk ----

fn drawDisk(app: *App) void {
    const s = app.screen;
    heading(app, str.disk_h);
    _ = s.text(ui.cx, ui.top + 1, str.disk_erase, .warn, ui.cw);
    const y0 = ui.top + 3;
    if (!app.disk_ok or app.disk_list.len == 0) {
        _ = s.text(ui.cx, y0, if (app.disk_ok) str.disk_none else str.disk_probe_failed, .danger, ui.cw);
        _ = s.text(ui.cx, y0 + 1, str.disk_rescan, .text, ui.cw);
    }
    for (app.disk_list, 0..) |d, i| {
        if (y0 + i >= app_mod.msgRow(app)) break;
        var size_buf: [16]u8 = undefined;
        var line_buf: [96]u8 = undefined;
        const tag = if (d.tooSmall()) str.disk_small else if (d.removable or std.mem.eql(u8, d.tran, "usb")) str.disk_usb else "";
        const line = std.fmt.bufPrint(&line_buf, "{s: <9} {s: >7}  {s: <26} {s}", .{
            d.name, disks.humanSize(&size_buf, d.size), d.model[0..@min(d.model.len, 26)], tag,
        }) catch d.name;
        row(app, @intCast(y0 + i), line, i == app.disk_cursor, if (d.tooSmall()) .dim else .text);
    }
    app.msg_y = @intCast(y0 + app.disk_list.len + 1);
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_move },
        .{ .key = str.k_enter, .what = str.f_choose },
        .{ .key = "R", .what = "look again" },
        .{ .key = str.k_esc, .what = str.f_back },
    });
}

fn handleDisk(app: *App, key: Key) void {
    const n = app.disk_list.len;
    switch (key) {
        .up => app.disk_cursor -|= 1,
        .down, .tab => if (app.disk_cursor + 1 < n) {
            app.disk_cursor += 1;
        },
        .char => |c| if (c == 'r' or c == 'R') {
            app.loadDisks();
            app.msg = null;
        },
        .enter => {
            if (n == 0) return;
            if (app.disk_list[app.disk_cursor].tooSmall()) {
                app.msg = str.disk_need;
                return;
            }
            app.next();
        },
        else => {},
    }
}

// ---- encryption ----
// focus: 0 = "No", 1 = "Yes", 2 = passphrase, 3 = again. Moving onto 0 or 1
// picks it, like a radio group.

fn drawEncryption(app: *App) void {
    const s = app.screen;
    heading(app, str.enc_h);
    const y = ui.top + 2;
    const on = app.encrypt;
    row(app, y, if (!on) "(*) No" else "( ) No", app.enc_focus == 0, .text);
    row(app, y + 1, if (on) "(*) Yes, with a passphrase" else "( ) Yes, with a passphrase", app.enc_focus == 1, .text);
    if (on) {
        field(app, y + 3, str.enc_pass, &app.enc_pass, app.enc_focus == 2);
        field(app, y + 4, str.enc_again, &app.enc_again, app.enc_focus == 3);
        app.msg_y = y + 5;
        _ = s.text(ui.cx, y + 6, str.enc_why, .warn, ui.cw);
    }
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_move },
        .{ .key = str.k_enter, .what = str.f_continue },
        .{ .key = str.k_esc, .what = str.f_back },
        .{ .key = str.k_quit, .what = str.f_quit },
    });
}

fn handleEncryption(app: *App, key: Key) void {
    const last: usize = if (app.encrypt) 3 else 1;
    switch (key) {
        .up => app.enc_focus -|= 1,
        .down, .tab => app.enc_focus = @min(app.enc_focus + 1, last),
        .enter => {
            if (!app.encrypt) return app.next();
            if (app.enc_focus < 3) {
                app.enc_focus += 1;
                return;
            }
            if (answers.checkPasswords(app.enc_pass.value(), app.enc_again.value())) |e| {
                app.msg = e;
                app.enc_focus = 2;
                return;
            }
            app.next();
        },
        else => {
            const f = switch (app.enc_focus) {
                2 => &app.enc_pass,
                3 => &app.enc_again,
                else => return,
            };
            if (f.edit(key)) app.msg = null;
        },
    }
    if (app.enc_focus <= 1) app.encrypt = app.enc_focus == 1;
}

// ---- account ----

const acct_labels = [_][]const u8{ str.acct_name, str.acct_user, str.acct_pass, str.acct_again, str.acct_host };

fn drawAccount(app: *App) void {
    const s = app.screen;
    heading(app, str.acct_h);
    for (&app.acct, 0..) |*f, i| {
        const y: u16 = @intCast(ui.top + 2 + i * 2);
        field(app, y, acct_labels[i], f, app.acct_focus == i);
        fieldError(app, y + 1, app.acct_err[i]);
    }
    _ = s.text(ui.cx, ui.top + 13, str.acct_sudo, .dim, ui.cw);
    app_mod.footer(app, &.{
        .{ .key = str.k_arrows, .what = str.f_field },
        .{ .key = str.k_enter, .what = str.f_continue },
        .{ .key = str.k_esc, .what = str.f_back },
        .{ .key = str.k_quit, .what = str.f_quit },
    });
}

/// Checks every field; returns the first bad one.
pub fn checkAccount(app: *App) ?usize {
    const a = &app.acct;
    app.acct_err = .{
        answers.checkFullName(a[0].value()),
        answers.checkUsername(a[1].value()),
        if (a[2].len == 0) "Enter a password" else null,
        if (a[2].len > 0 and !std.mem.eql(u8, a[2].value(), a[3].value())) "The two passwords differ" else null,
        answers.checkHostname(a[4].value()),
    };
    for (app.acct_err, 0..) |e, i| if (e != null) return i;
    return null;
}

fn handleAccount(app: *App, key: Key) void {
    switch (key) {
        .up => app.acct_focus -|= 1,
        .down, .tab => app.acct_focus = @min(app.acct_focus + 1, 4),
        .enter => {
            if (app.acct_focus < 4) {
                app.acct_focus += 1;
                return;
            }
            if (checkAccount(app)) |bad| {
                app.acct_focus = bad;
                return;
            }
            app.next();
        },
        else => {
            const i = app.acct_focus;
            if (!app.acct[i].edit(key)) return;
            app.acct_err[i] = null;
            if (i == 1) app.user_edited = app.acct[1].len > 0;
            if (i == 0 and !app.user_edited) {
                var buf: [40]u8 = undefined;
                app.acct[1].set(answers.suggestUsername(app.acct[0].value(), &buf));
            }
        },
    }
}
