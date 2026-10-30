//! sys.zig - the few Linux calls the installer needs, straight on std.os.linux.
//!
//! std.Io and std.process moved a lot between Zig 0.16 and 0.17; the raw
//! syscall wrappers did not, so everything that touches the OS goes through
//! here and the rest of the program never sees the difference.

const std = @import("std");
const linux = std.os.linux;

pub const Error = error{ SysFailed, NotFound, TooBig };

/// The process environment, set once by main.
pub var environ: [:null]const ?[*:0]const u8 = &.{};

/// `allocator.dupeZ`, which Zig 0.17 renamed; this works on both.
pub fn dupeZ(gpa: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const out = try gpa.allocSentinel(u8, s.len, 0);
    @memcpy(out, s);
    return out;
}

pub fn getenv(name: []const u8) ?[]const u8 {
    for (environ) |entry_opt| {
        const entry = std.mem.span(entry_opt orelse continue);
        if (entry.len > name.len and entry[name.len] == '=' and std.mem.startsWith(u8, entry, name))
            return entry[name.len + 1 ..];
    }
    return null;
}

fn failed(rc: usize) bool {
    return linux.errno(rc) != .SUCCESS;
}

fn interrupted(rc: usize) bool {
    return linux.errno(rc) == .INTR;
}

pub fn writeAll(fd: i32, bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const rc = linux.write(fd, rest.ptr, rest.len);
        if (interrupted(rc)) continue;
        if (failed(rc) or rc == 0) return;
        rest = rest[rc..];
    }
}

/// One read; 0 means end of file. EINTR is retried.
pub fn read(fd: i32, buf: []u8) Error!usize {
    while (true) {
        const rc = linux.read(fd, buf.ptr, buf.len);
        if (interrupted(rc)) continue;
        if (failed(rc)) return error.SysFailed;
        return rc;
    }
}

pub fn close(fd: i32) void {
    _ = linux.close(fd);
}

fn openZ(path: [*:0]const u8, flags: linux.O, mode: linux.mode_t) Error!i32 {
    while (true) {
        const rc = linux.open(path, flags, mode);
        if (interrupted(rc)) continue;
        return switch (linux.errno(rc)) {
            .SUCCESS => @intCast(rc),
            .NOENT => error.NotFound,
            else => error.SysFailed,
        };
    }
}

pub fn readFileAlloc(gpa: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    const z = try dupeZ(gpa, path);
    defer gpa.free(z);
    const fd = try openZ(z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    defer close(fd);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = try read(fd, &buf);
        if (n == 0) break;
        if (out.items.len + n > max) return error.TooBig;
        try out.appendSlice(gpa, buf[0..n]);
    }
    return out.toOwnedSlice(gpa);
}

/// Writes `data` to a new file only `mode` may read. Refuses to follow a
/// symlink at `path`.
pub fn writeSecretFile(path: [*:0]const u8, data: []const u8, mode: linux.mode_t) Error!void {
    _ = linux.unlink(path);
    const fd = try openZ(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, mode);
    defer close(fd);
    if (failed(linux.fchmod(fd, mode))) return error.SysFailed;
    var rest = data;
    while (rest.len > 0) {
        const rc = linux.write(fd, rest.ptr, rest.len);
        if (interrupted(rc)) continue;
        if (failed(rc) or rc == 0) return error.SysFailed;
        rest = rest[rc..];
    }
}

/// mkdir that accepts an existing directory and then forces its mode.
pub fn mkdirMode(path: [*:0]const u8, mode: linux.mode_t) Error!void {
    const rc = linux.mkdir(path, mode);
    switch (linux.errno(rc)) {
        .SUCCESS, .EXIST => {},
        else => return error.SysFailed,
    }
    if (failed(linux.chmod(path, mode))) return error.SysFailed;
}

pub fn unlink(path: [*:0]const u8) void {
    _ = linux.unlink(path);
}

pub fn exists(path: [*:0]const u8) bool {
    return !failed(linux.access(path, linux.F_OK));
}

pub fn isRoot() bool {
    return linux.geteuid() == 0;
}

pub fn sleepMs(ms: u32) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast(@as(u64, ms % 1000) * std.time.ns_per_ms) };
    _ = linux.nanosleep(&ts, null);
}

pub fn nowMs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1_000_000);
}

/// Waits up to `timeout_ms` for any of `fds` to be readable (or hung up).
/// Returns a bit per fd, bit i set when fds[i] is ready.
pub fn pollIn(fds: []const i32, timeout_ms: i32) u8 {
    var pfds: [4]linux.pollfd = undefined;
    for (fds, 0..) |fd, i| pfds[i] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
    const rc = linux.poll(&pfds, @intCast(fds.len), timeout_ms);
    if (failed(rc) or rc == 0) return 0;
    var mask: u8 = 0;
    for (pfds[0..fds.len], 0..) |p, i| {
        if (p.revents != 0) mask |= @as(u8, 1) << @intCast(i);
    }
    return mask;
}

// ---- terminal ----

pub const Termios = linux.termios;

pub fn rawMode(fd: i32) ?Termios {
    var t: Termios = undefined;
    if (failed(linux.tcgetattr(fd, &t))) return null;
    const orig = t;
    t.iflag.BRKINT = false;
    t.iflag.ICRNL = false;
    t.iflag.INPCK = false;
    t.iflag.ISTRIP = false;
    t.iflag.IXON = false;
    t.lflag.ECHO = false;
    t.lflag.ICANON = false;
    t.lflag.ISIG = false;
    t.lflag.IEXTEN = false;
    t.cc[@intFromEnum(linux.V.MIN)] = 1;
    t.cc[@intFromEnum(linux.V.TIME)] = 0;
    if (failed(linux.tcsetattr(fd, .FLUSH, &t))) return null;
    return orig;
}

pub fn restoreMode(fd: i32, t: Termios) void {
    _ = linux.tcsetattr(fd, .FLUSH, &t);
}

pub const Size = struct { cols: u16, rows: u16 };

pub fn winSize(fd: i32) Size {
    var ws: extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 } = undefined;
    const rc = linux.ioctl(fd, linux.T.IOCGWINSZ, @intFromPtr(&ws));
    if (failed(rc) or ws.col == 0 or ws.row == 0) return .{ .cols = 80, .rows = 25 };
    return .{ .cols = ws.col, .rows = ws.row };
}

// ---- processes ----

/// argv/envp ready for execve, built before fork so the child never allocates.
const Exec = struct {
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
};

fn prepare(arena: std.mem.Allocator, argv: []const []const u8) !Exec {
    const list = try arena.allocSentinel(?[*:0]const u8, argv.len, null);
    for (argv, 0..) |a, i| list[i] = (try dupeZ(arena, a)).ptr;
    return .{ .path = try findExe(arena, argv[0]), .argv = list.ptr };
}

/// PATH lookup; a name with a slash is used as given.
pub fn findExe(arena: std.mem.Allocator, name: []const u8) ![:0]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return dupeZ(arena, name);
    const path = getenv("PATH") orelse "/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    var it = std.mem.tokenizeScalar(u8, path, ':');
    while (it.next()) |dir| {
        const full = try std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, name }, 0);
        if (!failed(linux.access(full, linux.X_OK))) return full;
    }
    return error.NotFound;
}

pub fn which(arena: std.mem.Allocator, name: []const u8) bool {
    _ = findExe(arena, name) catch return false;
    return true;
}

const Stdio = struct { in: ?i32 = null, out: ?i32 = null, err: ?i32 = null, new_session: bool = false };

fn spawn(e: Exec, io: Stdio) Error!i32 {
    const envp: [*:null]const ?[*:0]const u8 = environ.ptr;
    const rc = linux.fork();
    if (failed(rc)) return error.SysFailed;
    if (rc != 0) return @intCast(rc);
    // child
    if (io.new_session) _ = linux.setsid();
    if (io.in) |fd| _ = linux.dup2(fd, 0);
    if (io.out) |fd| _ = linux.dup2(fd, 1);
    if (io.err) |fd| _ = linux.dup2(fd, 2);
    _ = linux.execve(e.path, e.argv, envp);
    linux.exit_group(127);
}

fn devNull() i32 {
    return openZ("/dev/null", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0) catch -1;
}

/// Exit code of a wait status; a signal reads as 128+signal.
fn exitCode(status: u32) u8 {
    if (status & 0x7f == 0) return @truncate(status >> 8);
    return 128 +% @as(u8, @truncate(status & 0x7f));
}

pub fn wait(pid: i32) u8 {
    var status: i32 = 0;
    while (true) {
        const rc = linux.waitpid(pid, @ptrCast(&status), 0);
        if (interrupted(rc)) continue;
        if (failed(rc)) return 255;
        return exitCode(@bitCast(status));
    }
}

/// Non-blocking wait: null while the child still runs.
pub fn tryWait(pid: i32) ?u8 {
    var status: i32 = 0;
    const rc = linux.waitpid(pid, @ptrCast(&status), linux.W.NOHANG);
    if (failed(rc)) return 255;
    if (rc == 0) return null;
    return exitCode(@bitCast(status));
}

pub const Output = struct { code: u8, stdout: []u8 };

/// Runs a command to completion, capturing stdout (stderr discarded).
/// A missing program is code 127 with empty output.
pub fn capture(gpa: std.mem.Allocator, argv: []const []const u8, max: usize) !Output {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const e = prepare(arena_state.allocator(), argv) catch |err| switch (err) {
        error.NotFound => return .{ .code = 127, .stdout = try gpa.alloc(u8, 0) },
        else => return err,
    };
    var fds: [2]i32 = undefined;
    if (failed(linux.pipe2(&fds, .{ .CLOEXEC = true }))) return error.SysFailed;
    const nul = devNull();
    defer if (nul >= 0) close(nul);
    const pid = spawn(e, .{ .in = nul, .out = fds[1], .err = nul }) catch |err| {
        close(fds[0]);
        close(fds[1]);
        return err;
    };
    close(fds[1]);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = read(fds[0], &buf) catch break;
        if (n == 0) break;
        if (out.items.len + n <= max) try out.appendSlice(gpa, buf[0..n]);
    }
    close(fds[0]);
    return .{ .code = wait(pid), .stdout = try out.toOwnedSlice(gpa) };
}

/// Runs a command on the terminal (nmtui, a shell) and waits for it.
pub fn interactive(gpa: std.mem.Allocator, argv: []const []const u8) u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const e = prepare(arena_state.allocator(), argv) catch return 127;
    const pid = spawn(e, .{}) catch return 255;
    return wait(pid);
}

pub const Child = struct { pid: i32, out: i32 };

/// Starts a command in its own session, stdin from /dev/null, stdout and
/// stderr together on one pipe the caller reads.
pub fn spawnPiped(gpa: std.mem.Allocator, argv: []const []const u8) !Child {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const e = try prepare(arena_state.allocator(), argv);
    var fds: [2]i32 = undefined;
    if (failed(linux.pipe2(&fds, .{ .CLOEXEC = true }))) return error.SysFailed;
    const nul = devNull();
    defer if (nul >= 0) close(nul);
    const pid = spawn(e, .{ .in = nul, .out = fds[1], .err = fds[1], .new_session = true }) catch |err| {
        close(fds[0]);
        close(fds[1]);
        return err;
    };
    close(fds[1]);
    return .{ .pid = pid, .out = fds[0] };
}

pub fn exit(code: u8) noreturn {
    linux.exit_group(code);
}

test "exitCode decodes normal exits and signals" {
    try std.testing.expectEqual(@as(u8, 0), exitCode(0));
    try std.testing.expectEqual(@as(u8, 3), exitCode(3 << 8));
    try std.testing.expectEqual(@as(u8, 128 + 9), exitCode(9));
}
