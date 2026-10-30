//! system.zig - what the installer asks of the live system: the network,
//! keyboard layouts, time zones, disks, loadkeys, nmtui, a shell, reboot.
//! In demo mode nothing here changes the machine.

const std = @import("std");
const sys = @import("sys.zig");
const disks = @import("disks.zig");

pub const Options = struct {
    demo: bool = false,
    engine: []const u8 = "/usr/local/bin/koompi-install",
    disks_file: ?[]const u8 = null,
    answers_dir: []const u8 = "/run/koompi",
    check_url: []const u8 = "https://github.com",
};

pub fn online(gpa: std.mem.Allocator, url: []const u8) bool {
    const out = sys.capture(gpa, &.{ "curl", "-fsI", "--max-time", "6", "-o", "/dev/null", url }, 0) catch return false;
    gpa.free(out.stdout);
    return out.code == 0;
}

fn lines(arena: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (it.next()) |l| {
        const s = std.mem.trim(u8, l, " \t");
        if (s.len > 0) try list.append(arena, s);
    }
    return list.toOwnedSlice(arena);
}

fn sortUnique(items: [][]const u8) []const []const u8 {
    std.mem.sort([]const u8, items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    var n: usize = 0;
    for (items) |it| {
        if (n > 0 and std.mem.eql(u8, items[n - 1], it)) continue;
        items[n] = it;
        n += 1;
    }
    return items[0..n];
}

/// Console keymaps: localectl, else the files under /usr/share/kbd/keymaps.
pub fn keymaps(arena: std.mem.Allocator) []const []const u8 {
    if (sys.capture(arena, &.{ "localectl", "list-keymaps", "--no-pager" }, 1 << 20)) |out| {
        if (out.code == 0) {
            const l = lines(arena, out.stdout) catch &.{};
            if (l.len > 0) return l;
        }
    } else |_| {}
    if (sys.capture(arena, &.{ "find", "/usr/share/kbd/keymaps", "-name", "*.map*", "-type", "f" }, 1 << 20)) |out| {
        var names: std.ArrayList([]const u8) = .empty;
        const l = lines(arena, out.stdout) catch &.{};
        for (l) |path| {
            const base = std.fs.path.basename(path);
            const dot = std.mem.indexOf(u8, base, ".map") orelse continue;
            names.append(arena, base[0..dot]) catch break;
        }
        if (names.items.len > 0) return sortUnique(names.items);
    } else |_| {}
    return &.{"us"};
}

/// Time zones: timedatectl, else the zone and link names in tzdata.zi.
pub fn timezones(arena: std.mem.Allocator) []const []const u8 {
    if (sys.capture(arena, &.{ "timedatectl", "list-timezones", "--no-pager" }, 1 << 20)) |out| {
        if (out.code == 0) {
            const l = lines(arena, out.stdout) catch &.{};
            if (l.len > 0) return l;
        }
    } else |_| {}
    if (sys.readFileAlloc(arena, "/usr/share/zoneinfo/tzdata.zi", 1 << 20)) |data| {
        const l = zonesFromTzdata(arena, data) catch &.{};
        if (l.len > 0) return l;
    } else |_| {}
    return &.{ "Asia/Phnom_Penh", "UTC" };
}

/// `Z name ...` declares a zone and `L target name` a link to one.
pub fn zonesFromTzdata(arena: std.mem.Allocator, data: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, data, '\n');
    while (it.next()) |line| {
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const kind = f.next() orelse continue;
        if (std.mem.eql(u8, kind, "Z")) {
            try names.append(arena, f.next() orelse continue);
        } else if (std.mem.eql(u8, kind, "L")) {
            _ = f.next() orelse continue;
            try names.append(arena, f.next() orelse continue);
        }
    }
    return sortUnique(names.items);
}

/// The demo's disks: an NVMe drive, a too-small eMMC and the live stick,
/// which the live-medium filter drops.
pub const demo_lsblk =
    \\{"blockdevices": [
    \\ {"name":"nvme0n1","path":"/dev/nvme0n1","size":512110190592,"model":"WD SN770 (demo)","type":"disk","rm":false,"ro":false,"tran":"nvme"},
    \\ {"name":"sda","path":"/dev/sda","size":1000204886016,"model":"Samsung 870 EVO (demo)","type":"disk","rm":false,"ro":false,"tran":"sata"},
    \\ {"name":"mmcblk0","path":"/dev/mmcblk0","size":15634268160,"model":"eMMC (demo)","type":"disk","rm":false,"ro":false,"tran":null},
    \\ {"name":"sdb","path":"/dev/sdb","size":31914983424,"model":"KOOMPI live USB","type":"disk","rm":true,"ro":false,"tran":"usb"}
    \\]}
;

pub const DiskProbe = struct { list: []const disks.Disk, ok: bool };

pub fn probeDisks(arena: std.mem.Allocator, opts: Options) DiskProbe {
    const json, const live = blk: {
        if (opts.disks_file) |f| {
            const data = sys.readFileAlloc(arena, f, 1 << 20) catch return .{ .list = &.{}, .ok = false };
            break :blk .{ data, liveMedium(arena) };
        }
        if (opts.demo) break :blk .{ demo_lsblk, @as(?[]const u8, "sdb") };
        const out = sys.capture(arena, &disks.lsblk_argv, 1 << 20) catch return .{ .list = &.{}, .ok = false };
        if (out.code != 0) return .{ .list = &.{}, .ok = false };
        break :blk .{ out.stdout, liveMedium(arena) };
    };
    const list = disks.parse(arena, json, live) catch return .{ .list = &.{}, .ok = false };
    return .{ .list = list, .ok = true };
}

/// The disk the live system booted from, or null when it cannot be told
/// (copytoram, not on archiso).
fn liveMedium(arena: std.mem.Allocator) ?[]const u8 {
    const src = sys.capture(arena, &.{ "findmnt", "-no", "SOURCE", "/run/archiso/bootmnt" }, 4096) catch return null;
    if (src.code != 0) return null;
    const dev = disks.firstLine(src.stdout);
    if (dev.len == 0) return null;
    const pk = sys.capture(arena, &.{ "lsblk", "-no", "PKNAME", dev }, 4096) catch return disks.liveDisk(src.stdout, "");
    return disks.liveDisk(src.stdout, pk.stdout);
}

/// Applies a console layout at once, so the passwords typed next use it.
pub fn loadkeys(gpa: std.mem.Allocator, opts: Options, map: []const u8) void {
    if (opts.demo or !sys.isRoot()) return;
    const out = sys.capture(gpa, &.{ "loadkeys", map }, 0) catch return;
    gpa.free(out.stdout);
}

pub fn reboot(gpa: std.mem.Allocator, opts: Options) bool {
    if (opts.demo) return true;
    const out = sys.capture(gpa, &.{ "systemctl", "reboot" }, 0) catch return false;
    gpa.free(out.stdout);
    return out.code == 0;
}

pub fn shellArgv(arena: std.mem.Allocator) []const []const u8 {
    if (sys.which(arena, "bash")) return &.{ "bash", "-l" };
    return &.{"sh"};
}

const t = std.testing;

test "tzdata.zi zones and links" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const data = "# version 2026a\nR K 1 2 - Ja 1 0 0 -\nZ Asia/Phnom_Penh 6:59 - LMT 1906\nZ Asia/Bangkok 6:42:4 - LMT 1880\nL Asia/Bangkok Asia/Vientiane\nZ Asia/Bangkok 1 - X\n";
    const zones = try zonesFromTzdata(arena.allocator(), data);
    try t.expectEqual(@as(usize, 3), zones.len);
    try t.expectEqualStrings("Asia/Bangkok", zones[0]);
    try t.expectEqualStrings("Asia/Phnom_Penh", zones[1]);
    try t.expectEqualStrings("Asia/Vientiane", zones[2]);
}

test "demo disks drop the live stick" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const p = probeDisks(arena.allocator(), .{ .demo = true });
    try t.expect(p.ok);
    try t.expectEqual(@as(usize, 3), p.list.len);
    for (p.list) |d| try t.expect(!std.mem.eql(u8, d.name, "sdb"));
}
