# koompi-installer

The KOOMPI OS installer's face. The live ISO opens it on tty1. It asks a few
questions, writes them to an answers file, runs the install engine and shows
its progress. It does no disk work itself: the engine does, so the installed
system is the same desktop `install.sh` sets up.

Screens and copy: [`docs/ui-ux.md`](docs/ui-ux.md).

## Build

Zig 0.16 or 0.17, no dependencies.

```sh
cd installer
zig build -Doptimize=ReleaseSafe   # -> zig-out/bin/koompi-installer
zig build test                     # unit tests, on the build host
```

The default target is `x86_64-linux-musl` and nothing links libc, so the
binary is static and the same on any build host. The ISO copies it to
`/usr/local/bin/koompi-installer`.

## The engine contract

The installer writes `/run/koompi/answers.json` (directory 0700, file 0600)
and runs:

```sh
/usr/local/bin/koompi-install --answers /run/koompi/answers.json
```

```json
{
  "version": 1,
  "disk": "/dev/nvme0n1",
  "encrypt": false,
  "encryption_password": "",
  "hostname": "koompi",
  "full_name": "Sok Dara",
  "username": "dara",
  "password": "secret",
  "timezone": "Asia/Phnom_Penh",
  "keyboard": "us",
  "locale": "en_US.UTF-8"
}
```

- The engine deletes the file once read; the installer deletes it again when
  the engine exits, in case it did not. The file is never logged or shown.
- The engine runs in its own session, stdin `/dev/null`, stdout and stderr
  on one pipe. Lines starting `@@koompi ` are progress:
  `@@koompi step <n>/<total> <label>`, `@@koompi done`,
  `@@koompi fail <reason>`. Everything else is log text; the last 10 lines
  are shown. Exit 0 is success.
- The full log is the engine's, at `/var/log/koompi-install.log`.

## Running it

```
koompi-installer [--engine PATH] [--demo] [--disks FILE]
                 [--answers-dir DIR] [--check-url URL] [--allow-host]
```

| Option / env | Effect |
|---|---|
| `--engine PATH`, `KOOMPI_ENGINE` | engine to run (default `/usr/local/bin/koompi-install`) |
| `--demo` | touches nothing: built-in fake disks, no `loadkeys`, no reboot, answers under `$XDG_RUNTIME_DIR/koompi-demo`. Needs `--engine`. |
| `--disks FILE` | read the disk list from saved `lsblk -J -b -d -o NAME,PATH,SIZE,MODEL,TYPE,RM,RO,TRAN` output |
| `--answers-dir DIR` | where `answers.json` goes (default `/run/koompi`) |
| `--check-url URL` | what the network check fetches (default `https://github.com`) |
| `--allow-host` | run as root outside the live ISO (no `/run/archiso`) |
| `NO_COLOR` | no colors, reverse video for the selection |

Without `--demo` it refuses to start unless it is root and `/run/archiso`
exists. Exit codes: 0 installed (the person restarted or chose to stay), 1
quit or gave up after a failure, 2 bad command line or not allowed here.

## Trying it on a dev machine

```sh
zig build
./zig-out/bin/koompi-installer --demo --engine test/fake-engine.sh
```

`test/fake-engine.sh` reads and deletes the answers file and prints four
steps. `KOOMPI_FAKE_FAIL=2` fails in step 2, `KOOMPI_FAKE_DELAY=3` slows it.

`python3 test/drive.py zig-out/bin/koompi-installer` runs the demo in a pty
at 80x25 with `TERM=linux` and prints each screen: a full install, a failed
one (shell and retry), no network, and stopping a running install.

## Files

| File | Role |
|---|---|
| `src/main.zig` | options, safety checks, start-up |
| `src/app.zig` | state, page flow, chrome, event loop |
| `src/pages.zig` | welcome, network, keyboard, time zone, disk, encryption, account |
| `src/finish.zig` | review, install (engine run and progress), done |
| `src/answers.zig` | answers JSON and the name/password checks |
| `src/disks.zig` | lsblk parsing, live-medium filter, sizes |
| `src/progress.zig` | `@@koompi` lines and the log tail |
| `src/system.zig` | network check, keymaps, time zones, disks, loadkeys, reboot |
| `src/input.zig` | keys, text fields, the searchable list |
| `src/ui.zig` | the cell grid and its ANSI output |
| `src/sys.zig` | the Linux calls, on `std.os.linux` (same on Zig 0.16 and 0.17) |
| `src/strings.zig` | every word on screen |
| `src/post_install.sh` | not used by the installer; left from the old scaffold because three repo tests still source it |
