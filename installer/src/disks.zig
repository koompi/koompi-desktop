//! disks.zig - the disks the person may install to, from
//! `lsblk -J -b -d -o NAME,PATH,SIZE,MODEL,TYPE,RM,RO,TRAN`.

const std = @import("std");

pub const min_bytes: u64 = 20 * 1000 * 1000 * 1000;

pub const lsblk_argv = [_][]const u8{ "lsblk", "-J", "-b", "-d", "-o", "NAME,PATH,SIZE,MODEL,TYPE,RM,RO,TRAN" };

pub const Disk = struct {
    name: []const u8,
    path: []const u8,
    size: u64,
    model: []const u8,
    tran: []const u8,
    removable: bool,

    pub fn tooSmall(d: Disk) bool {
        return d.size < min_bytes;
    }
};

/// lsblk prints booleans as true/false on new versions and "0"/"1" or 0/1 on
/// old ones; sizes as numbers with -b, strings on some builds.
fn asBool(v: ?std.json.Value) bool {
    const x = v orelse return false;
    return switch (x) {
        .bool => |b| b,
        .integer => |i| i != 0,
        .string => |s| std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "true"),
        else => false,
    };
}

fn asU64(v: ?std.json.Value) u64 {
    const x = v orelse return 0;
    return switch (x) {
        .integer => |i| if (i < 0) 0 else @intCast(i),
        .float => |f| if (f < 0) 0 else @intFromFloat(f),
        .string, .number_string => |s| std.fmt.parseInt(u64, std.mem.trim(u8, s, " "), 10) catch 0,
        else => 0,
    };
}

fn asStr(v: ?std.json.Value) []const u8 {
    const x = v orelse return "";
    return switch (x) {
        .string => |s| std.mem.trim(u8, s, " "),
        else => "",
    };
}

fn isVirtual(name: []const u8) bool {
    const prefixes = [_][]const u8{ "zram", "loop", "sr", "ram", "fd" };
    for (prefixes) |p| if (std.mem.startsWith(u8, name, p)) return true;
    return false;
}

/// Disks fit to install on, in lsblk order. `live` is the kernel name of
/// the disk the live system booted from (excluded), if known. Strings point
/// into `arena`.
pub fn parse(arena: std.mem.Allocator, json: []const u8, live: ?[]const u8) ![]Disk {
    const root = try std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
    if (root != .object) return error.BadLsblk;
    const devs = root.object.get("blockdevices") orelse return error.BadLsblk;
    if (devs != .array) return error.BadLsblk;
    var out: std.ArrayList(Disk) = .empty;
    for (devs.array.items) |dev| {
        if (dev != .object) continue;
        const o = dev.object;
        const name = asStr(o.get("name"));
        if (name.len == 0) continue;
        if (!std.mem.eql(u8, asStr(o.get("type")), "disk")) continue;
        if (asBool(o.get("ro"))) continue;
        if (isVirtual(name)) continue;
        if (live) |l| if (std.mem.eql(u8, l, name)) continue;
        const size = asU64(o.get("size"));
        if (size == 0) continue; // empty card reader
        const path = asStr(o.get("path"));
        try out.append(arena, .{
            .name = name,
            .path = if (path.len > 0) path else try std.fmt.allocPrint(arena, "/dev/{s}", .{name}),
            .size = size,
            .model = asStr(o.get("model")),
            .tran = asStr(o.get("tran")),
            .removable = asBool(o.get("rm")),
        });
    }
    return out.toOwnedSlice(arena);
}

/// The live medium's disk name from `findmnt -no SOURCE /run/archiso/bootmnt`
/// and `lsblk -no PKNAME <source>`. A partition has a parent; a medium
/// written whole (iso9660 on the device) does not, so the source is the disk.
pub fn liveDisk(findmnt_out: []const u8, pkname_out: []const u8) ?[]const u8 {
    const pk = firstLine(pkname_out);
    if (pk.len > 0) return pk;
    const src = firstLine(findmnt_out);
    if (!std.mem.startsWith(u8, src, "/dev/")) return null;
    const base = src["/dev/".len..];
    if (base.len == 0 or std.mem.indexOfScalar(u8, base, '/') != null) return null;
    return base;
}

pub fn firstLine(s: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, s, '\n') orelse s.len;
    return std.mem.trim(u8, s[0..end], " \t\r");
}

/// Sizes as disks are sold: decimal GB/TB.
pub fn humanSize(buf: []u8, bytes: u64) []const u8 {
    const gb = 1000 * 1000 * 1000;
    const r = if (bytes >= 1000 * gb)
        std.fmt.bufPrint(buf, "{d}.{d} TB", .{ bytes / (1000 * gb), (bytes % (1000 * gb)) / (100 * gb) })
    else if (bytes >= gb)
        std.fmt.bufPrint(buf, "{d} GB", .{bytes / gb})
    else
        std.fmt.bufPrint(buf, "{d} MB", .{bytes / (1000 * 1000)});
    return r catch "?";
}

const t = std.testing;

const sample =
    \\{
    \\   "blockdevices": [
    \\      {"name":"sda", "path":"/dev/sda", "size":31914983424, "model":"SanDisk Ultra", "type":"disk", "rm":true, "ro":false, "tran":"usb"},
    \\      {"name":"sdb", "path":"/dev/sdb", "size":8000000000, "model":"Old stick", "type":"disk", "rm":true, "ro":false, "tran":"usb"},
    \\      {"name":"sr0", "path":"/dev/sr0", "size":1073741312, "model":"DVD", "type":"rom", "rm":true, "ro":false, "tran":"sata"},
    \\      {"name":"loop0", "path":"/dev/loop0", "size":900000000, "model":null, "type":"loop", "rm":false, "ro":true, "tran":null},
    \\      {"name":"zram0", "path":"/dev/zram0", "size":4000000000, "model":null, "type":"disk", "rm":false, "ro":false, "tran":null},
    \\      {"name":"nvme0n1", "path":"/dev/nvme0n1", "size":512110190592, "model":"WD SN770 ", "type":"disk", "rm":false, "ro":false, "tran":"nvme"},
    \\      {"name":"sdc", "path":"/dev/sdc", "size":2000398934016, "model":"Locked", "type":"disk", "rm":false, "ro":true, "tran":"sata"},
    \\      {"name":"sdd", "path":"/dev/sdd", "size":0, "model":"Card reader", "type":"disk", "rm":true, "ro":false, "tran":"usb"}
    \\   ]
    \\}
;

test "lsblk parsing keeps writable real disks and drops the live medium" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const disks = try parse(arena.allocator(), sample, "sda");
    try t.expectEqual(@as(usize, 2), disks.len);
    try t.expectEqualStrings("sdb", disks[0].name);
    try t.expect(disks[0].tooSmall());
    try t.expect(disks[0].removable);
    try t.expectEqualStrings("/dev/nvme0n1", disks[1].path);
    try t.expectEqualStrings("WD SN770", disks[1].model);
    try t.expectEqual(@as(u64, 512110190592), disks[1].size);
    try t.expect(!disks[1].tooSmall());
}

test "lsblk parsing without a known live medium keeps the stick" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const disks = try parse(arena.allocator(), sample, null);
    try t.expectEqual(@as(usize, 3), disks.len);
    try t.expectEqualStrings("sda", disks[0].name);
}

test "lsblk parsing reads old-style string flags and sizes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old =
        \\{"blockdevices": [
        \\  {"name":"sda", "size":"256060514304", "model":"Samsung", "type":"disk", "rm":"0", "ro":"0", "tran":"sata"},
        \\  {"name":"sdb", "size":"256060514304", "model":"RO", "type":"disk", "rm":"0", "ro":"1", "tran":"sata"}
        \\]}
    ;
    const disks = try parse(arena.allocator(), old, null);
    try t.expectEqual(@as(usize, 1), disks.len);
    try t.expectEqualStrings("/dev/sda", disks[0].path);
    try t.expectEqual(@as(u64, 256060514304), disks[0].size);
    try t.expect(!disks[0].removable);
}

test "lsblk parsing rejects garbage" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectError(error.BadLsblk, parse(arena.allocator(), "{\"x\":1}", null));
    try t.expect(std.meta.isError(parse(arena.allocator(), "not json", null)));
    const empty = try parse(arena.allocator(), "{\"blockdevices\":[]}", null);
    try t.expectEqual(@as(usize, 0), empty.len);
}

test "live medium resolution" {
    try t.expectEqualStrings("sdb", liveDisk("/dev/sdb1\n", "sdb\n").?);
    try t.expectEqualStrings("sdb", liveDisk("/dev/sdb\n", "\n").?);
    try t.expectEqualStrings("nvme1n1", liveDisk("/dev/nvme1n1p2\n", "nvme1n1").?);
    try t.expect(liveDisk("", "") == null); // copytoram, nothing mounted
    try t.expect(liveDisk("airootfs\n", "") == null);
    try t.expect(liveDisk("/dev/disk/by-label/X\n", "") == null);
}

test "human sizes" {
    var buf: [32]u8 = undefined;
    try t.expectEqualStrings("512 GB", humanSize(&buf, 512110190592));
    try t.expectEqualStrings("2.0 TB", humanSize(&buf, 2000398934016));
    try t.expectEqualStrings("1.5 TB", humanSize(&buf, 1500000000000));
    try t.expectEqualStrings("800 MB", humanSize(&buf, 800000000));
}
