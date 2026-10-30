//! answers.zig - what the person chose, its checks, and the answers file the
//! engine reads (`koompi-install --answers <file>`, contract version 1).

const std = @import("std");

pub const Answers = struct {
    disk: []const u8 = "",
    encrypt: bool = false,
    encryption_password: []const u8 = "",
    hostname: []const u8 = "koompi",
    full_name: []const u8 = "",
    username: []const u8 = "",
    password: []const u8 = "",
    timezone: []const u8 = "Asia/Phnom_Penh",
    keyboard: []const u8 = "us",
    locale: []const u8 = "en_US.UTF-8",
};

/// Writes a JSON string literal. Quotes, backslashes and every control
/// character are escaped; other bytes (UTF-8 included) pass through.
pub fn writeJsonString(w: *std.ArrayList(u8), gpa: std.mem.Allocator, s: []const u8) !void {
    try w.append(gpa, '"');
    for (s) |c| switch (c) {
        '"' => try w.appendSlice(gpa, "\\\""),
        '\\' => try w.appendSlice(gpa, "\\\\"),
        '\n' => try w.appendSlice(gpa, "\\n"),
        '\r' => try w.appendSlice(gpa, "\\r"),
        '\t' => try w.appendSlice(gpa, "\\t"),
        0...8, 11, 12, 14...0x1f, 0x7f => {
            var buf: [6]u8 = undefined;
            _ = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch unreachable;
            try w.appendSlice(gpa, &buf);
        },
        else => try w.append(gpa, c),
    };
    try w.append(gpa, '"');
}

/// The answers file body. Caller frees; it holds passwords, so the caller
/// also wipes it (`std.crypto.secureZero`) before freeing.
pub fn toJson(gpa: std.mem.Allocator, a: Answers) ![]u8 {
    var w: std.ArrayList(u8) = .empty;
    errdefer {
        std.crypto.secureZero(u8, w.items);
        w.deinit(gpa);
    }
    try w.appendSlice(gpa, "{\n  \"version\": 1,\n");
    const fields = .{
        .{ "disk", a.disk },
        .{ "encrypt", a.encrypt },
        .{ "encryption_password", if (a.encrypt) a.encryption_password else "" },
        .{ "hostname", a.hostname },
        .{ "full_name", a.full_name },
        .{ "username", a.username },
        .{ "password", a.password },
        .{ "timezone", a.timezone },
        .{ "keyboard", a.keyboard },
        .{ "locale", a.locale },
    };
    inline for (fields, 0..) |f, i| {
        try w.appendSlice(gpa, "  \"" ++ f[0] ++ "\": ");
        if (@TypeOf(f[1]) == bool) {
            try w.appendSlice(gpa, if (f[1]) "true" else "false");
        } else {
            try writeJsonString(&w, gpa, f[1]);
        }
        try w.appendSlice(gpa, if (i + 1 < fields.len) ",\n" else "\n");
    }
    try w.appendSlice(gpa, "}\n");
    return w.toOwnedSlice(gpa);
}

// ---- checks: null means fine, otherwise the problem in a few words ----

const reserved_users = [_][]const u8{
    "root",     "bin",     "daemon",  "mail",    "ftp",       "http",      "nobody",   "dbus",
    "uuidd",    "dhcpcd",  "polkitd", "rtkit",   "avahi",     "colord",    "git",      "sddm",
    "gdm",      "ntp",     "tss",     "usbmux",  "geoclue",   "flatpak",   "alpm",     "adm",
    "wheel",    "sys",     "games",   "lp",      "tty",       "kmem",      "audio",    "video",
    "users",    "input",   "kvm",     "render",  "storage",   "network",   "optical",  "scanner",
    "power",    "rfkill",  "utmp",    "locate",  "log",       "uucp",      "disk",     "floppy",
    "mem",      "proc",    "smmsp",   "sgx",     "nm-openvpn", "nm-openconnect", "cups", "saned",
    "brltty",   "dnsmasq", "mysql",   "postgres", "docker",   "libvirt",   "qemu",     "koompi-live",
};

pub fn checkUsername(name: []const u8) ?[]const u8 {
    if (name.len == 0) return "Pick a user name";
    if (name.len > 32) return "At most 32 characters";
    if (!(std.ascii.isLower(name[0]) or name[0] == '_')) return "Start with a small letter";
    for (name[1..]) |c| {
        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_' or c == '-'))
            return "Use a-z, 0-9, - and _ only";
    }
    if (std.mem.startsWith(u8, name, "systemd-")) return "That name is taken by the system";
    for (reserved_users) |r| if (std.mem.eql(u8, name, r)) return "That name is taken by the system";
    return null;
}

/// One RFC 1123 label: 1-63 of a-z A-Z 0-9 and '-', no '-' at either end.
pub fn checkHostname(name: []const u8) ?[]const u8 {
    if (name.len == 0) return "Name this computer";
    if (name.len > 63) return "At most 63 characters";
    for (name) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '-')) return "Use letters, digits and - only";
    }
    if (name[0] == '-' or name[name.len - 1] == '-') return "Cannot start or end with -";
    return null;
}

pub fn checkFullName(name: []const u8) ?[]const u8 {
    if (name.len > 64) return "At most 64 characters";
    for (name) |c| {
        if (c < 0x20 or c == 0x7f or c == ':' or c == ',') return "No : or , in the name";
    }
    return null;
}

pub fn checkPasswords(first: []const u8, second: []const u8) ?[]const u8 {
    if (first.len == 0) return "Enter a password";
    if (!std.mem.eql(u8, first, second)) return "The two passwords differ";
    return null;
}

/// A user name guessed from the full name: its first word, lowercased,
/// letters and digits only. Empty when nothing usable is left.
pub fn suggestUsername(full_name: []const u8, buf: []u8) []const u8 {
    var n: usize = 0;
    var it = std.mem.tokenizeScalar(u8, full_name, ' ');
    const word = it.next() orelse return buf[0..0];
    for (word) |c| {
        if (n == buf.len or n == 32) break;
        const l = std.ascii.toLower(c);
        if (std.ascii.isLower(l) or (n > 0 and std.ascii.isDigit(l))) {
            buf[n] = l;
            n += 1;
        }
    }
    const s = buf[0..n];
    if (checkUsername(s) != null) return buf[0..0];
    return s;
}

const t = std.testing;

test "answers JSON escapes quotes, backslashes and control characters" {
    const a = Answers{
        .disk = "/dev/sda",
        .full_name = "Sok \"Dara\" \\ Test",
        .username = "dara",
        .password = "p\"w\\d\n\t\x01\x7f",
        .encrypt = true,
        .encryption_password = "lu\"ks",
    };
    const json = try toJson(t.allocator, a);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"full_name\": \"Sok \\\"Dara\\\" \\\\ Test\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"password\": \"p\\\"w\\\\d\\n\\t\\u0001\\u007f\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"version\": 1,") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"encrypt\": true,") != null);

    // It must parse back to the same values.
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, json, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try t.expectEqualStrings(a.password, obj.get("password").?.string);
    try t.expectEqualStrings(a.full_name, obj.get("full_name").?.string);
    try t.expectEqualStrings("lu\"ks", obj.get("encryption_password").?.string);
    try t.expectEqualStrings("Asia/Phnom_Penh", obj.get("timezone").?.string);
    try t.expectEqual(@as(i64, 1), obj.get("version").?.integer);
    try t.expectEqual(@as(usize, 11), obj.count());
}

test "answers JSON drops the encryption password when not encrypting" {
    const json = try toJson(t.allocator, .{ .encrypt = false, .encryption_password = "left over" });
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "left over") == null);
    try t.expect(std.mem.indexOf(u8, json, "\"encryption_password\": \"\",") != null);
}

test "answers JSON keeps UTF-8 names as they are" {
    const json = try toJson(t.allocator, .{ .full_name = "សុខ ដារា" });
    defer t.allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, json, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("សុខ ដារា", parsed.value.object.get("full_name").?.string);
}

test "username rules" {
    try t.expect(checkUsername("dara") == null);
    try t.expect(checkUsername("_svc") == null);
    try t.expect(checkUsername("a1-b_c") == null);
    try t.expect(checkUsername("abcdefghijklmnopqrstuvwxyz012345") == null); // 32
    try t.expect(checkUsername("abcdefghijklmnopqrstuvwxyz0123456") != null); // 33
    try t.expect(checkUsername("") != null);
    try t.expect(checkUsername("Dara") != null);
    try t.expect(checkUsername("1dara") != null);
    try t.expect(checkUsername("-dara") != null);
    try t.expect(checkUsername("da ra") != null);
    try t.expect(checkUsername("dara.k") != null);
    try t.expect(checkUsername("root") != null);
    try t.expect(checkUsername("nobody") != null);
    try t.expect(checkUsername("systemd-network") != null);
}

test "hostname rules" {
    try t.expect(checkHostname("koompi") == null);
    try t.expect(checkHostname("Koompi-E13") == null);
    try t.expect(checkHostname("a") == null);
    try t.expect(checkHostname("") != null);
    try t.expect(checkHostname("-koompi") != null);
    try t.expect(checkHostname("koompi-") != null);
    try t.expect(checkHostname("koompi.local") != null);
    try t.expect(checkHostname("koompi_pc") != null);
    const a63 = "abcdefghij" ++ "abcdefghij" ++ "abcdefghij" ++ "abcdefghij" ++ "abcdefghij" ++ "abcdefghij" ++ "abc";
    try t.expect(checkHostname(a63) == null);
    try t.expect(checkHostname(a63 ++ "d") != null);
}

test "full name, passwords and the username guess" {
    try t.expect(checkFullName("Sok Dara") == null);
    try t.expect(checkFullName("") == null);
    try t.expect(checkFullName("a:b") != null);
    try t.expect(checkPasswords("x", "x") == null);
    try t.expect(checkPasswords("", "") != null);
    try t.expect(checkPasswords("x", "y") != null);
    var buf: [40]u8 = undefined;
    try t.expectEqualStrings("sok", suggestUsername("Sok Dara", &buf));
    try t.expectEqualStrings("odara2", suggestUsername("O'Dara2", &buf));
    try t.expectEqualStrings("", suggestUsername("", &buf));
    try t.expectEqualStrings("", suggestUsername("Root", &buf));
    try t.expectEqualStrings("", suggestUsername("សុខ", &buf));
}
