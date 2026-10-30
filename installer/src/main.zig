//! koompi-installer - the KOOMPI OS installer's face. It asks the questions
//! on the live ISO's console, writes the answers file, runs the engine
//! (`koompi-install --answers <file>`) and shows its progress.
//!
//! Exit codes: 0 installed (the person chose to stay or restart), 1 quit or
//! gave up after a failure, 2 bad command line or not allowed to run here.

const std = @import("std");
const sys = @import("sys.zig");
const ui = @import("ui.zig");
const system = @import("system.zig");
const app_mod = @import("app.zig");

const usage =
    \\Usage: koompi-installer [options]
    \\
    \\  --engine PATH       install engine (default /usr/local/bin/koompi-install,
    \\                      or $KOOMPI_ENGINE)
    \\  --demo              touch nothing: fake disks, no loadkeys, no reboot,
    \\                      answers in $XDG_RUNTIME_DIR/koompi-demo; needs --engine
    \\  --disks FILE        read the disk list from an lsblk -J file
    \\  --answers-dir DIR   where answers.json is written (default /run/koompi)
    \\  --check-url URL     address the network check fetches
    \\  --allow-host        run outside the live ISO (no /run/archiso)
    \\  -h, --help          this text
    \\
;

const default_engine = "/usr/local/bin/koompi-install";

fn die(msg: []const u8) noreturn {
    sys.writeAll(2, "koompi-installer: ");
    sys.writeAll(2, msg);
    sys.writeAll(2, "\n");
    sys.exit(2);
}

const Parsed = struct { opts: system.Options, allow_host: bool, engine_given: bool, dir_given: bool };

fn parseArgs(argv: []const [*:0]const u8) Parsed {
    var p = Parsed{ .opts = .{}, .allow_host = false, .engine_given = false, .dir_given = false };
    if (sys.getenv("KOOMPI_ENGINE")) |e| if (e.len > 0) {
        p.opts.engine = e;
        p.engine_given = true;
    };
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = std.mem.span(argv[i]);
        const needs_value = std.mem.eql(u8, a, "--engine") or std.mem.eql(u8, a, "--disks") or
            std.mem.eql(u8, a, "--answers-dir") or std.mem.eql(u8, a, "--check-url");
        if (needs_value) {
            i += 1;
            if (i >= argv.len) die("missing value after an option; see --help");
            const v = std.mem.span(argv[i]);
            if (std.mem.eql(u8, a, "--engine")) {
                p.opts.engine = v;
                p.engine_given = true;
            } else if (std.mem.eql(u8, a, "--disks")) {
                p.opts.disks_file = v;
            } else if (std.mem.eql(u8, a, "--answers-dir")) {
                p.opts.answers_dir = v;
                p.dir_given = true;
            } else p.opts.check_url = v;
        } else if (std.mem.eql(u8, a, "--demo")) {
            p.opts.demo = true;
        } else if (std.mem.eql(u8, a, "--allow-host")) {
            p.allow_host = true;
        } else if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            sys.writeAll(1, usage);
            sys.exit(0);
        } else die("unknown option; see --help");
    }
    return p;
}

var screen: ui.Screen = .{};

pub fn main(init: std.process.Init.Minimal) u8 {
    sys.environ = init.environ.block.slice;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const gpa = std.heap.page_allocator;

    const p = parseArgs(init.args.vector);
    var opts = p.opts;
    if (opts.demo) {
        if (!p.engine_given or std.mem.eql(u8, opts.engine, default_engine))
            die("--demo needs --engine <fake engine>, e.g. installer/test/fake-engine.sh");
        if (!p.dir_given) {
            opts.answers_dir = if (sys.getenv("XDG_RUNTIME_DIR")) |r|
                std.fmt.allocPrint(arena, "{s}/koompi-demo", .{r}) catch die("out of memory")
            else
                std.fmt.allocPrint(arena, "/tmp/koompi-demo-{d}", .{std.os.linux.getuid()}) catch die("out of memory");
        }
    } else {
        if (!sys.isRoot()) die("run as root on the live ISO, or try --demo");
        if (!p.allow_host and !sys.exists("/run/archiso")) die("not on the KOOMPI live ISO (no /run/archiso); --allow-host to run anyway");
    }
    if (sys.getenv("NO_COLOR")) |v| ui.no_color = v.len > 0;

    if (sys.rawMode(0)) |t| sys.restoreMode(0, t) else die("needs a terminal on stdin");

    var app = app_mod.App{ .gpa = gpa, .arena = arena, .opts = opts, .screen = &screen };
    app.acct[4].set("koompi");
    app.kb.init(gpa, system.keymaps(arena), "us") catch die("out of memory");
    app.tz.init(gpa, system.timezones(arena), "Asia/Phnom_Penh") catch die("out of memory");

    const code = app_mod.run(&app) catch 1;
    app.wipeSecrets();
    if (app.child) |c| {
        // quit while the engine runs (stdin gone): do not leave it orphaned
        _ = std.os.linux.kill(-c.pid, .TERM);
        _ = sys.wait(c.pid);
        if (app.answers_path.len > 0) sys.unlink(app.answers_path);
    }
    return code;
}

test {
    _ = @import("sys.zig");
    _ = @import("answers.zig");
    _ = @import("disks.zig");
    _ = @import("progress.zig");
    _ = @import("input.zig");
    _ = @import("system.zig");
    _ = @import("ui.zig");
    _ = @import("app.zig");
}
