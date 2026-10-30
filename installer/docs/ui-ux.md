# koompi-installer: screens and look

What is built, not a wish list. The words on screen live in
`src/strings.zig`; change them there.

## Where it runs

The live ISO's tty1: an 80x25 VGA console, `TERM=linux`, 16 colors, the
kernel's console font. So:

- ASCII and box-drawing glyphs only. No emoji, no Khmer (the font has
  neither), English only for now. Any other character from the engine's log
  shows as `?`.
- Colors are the 8 ANSI colors plus bold for bright. Meaning never rests on
  color alone: errors start with `!`, finished steps with `+`, the current
  step and the selected row with `>`.
- At least 80x24. A bigger terminal gets the same 80x25 frame, centered; a
  smaller one gets "Make the window at least 80x24."
- `NO_COLOR` drops color; the selection becomes reverse video.

## Frame

```
  KOOMPI OS Installer                                DEMO - no disk is touched
                                                       (demo badge: --demo only)
  + Welcome      │  Install on which disk?
  + Network      │  Everything on the chosen disk is erased.
  + Keyboard     │
  + Time zone    │  > nvme0n1    512 GB  WD SN770
  > Disk         │    sda        1.0 TB  Samsung 870 EVO
    Encryption   │    mmcblk0     15 GB  eMMC                       too small
    Account      │
    Review       │
    Install      │

  Up/Down move   Enter choose   R look again   Esc back
```

Header bar (white on blue), step rail on the left, the page on the right,
the keys that work on this page on the bottom row. A page has one job and
one way forward.

## Keys everywhere

| Key | Does |
|---|---|
| Enter | continue / choose |
| Esc | back one page (not while installing) |
| Up/Down, Tab | move between rows or fields |
| Ctrl+U | clear the field |
| Ctrl+C | quit, after a Y/N box; exit code 1. While the engine runs it asks to stop the install instead. |

Shift+Tab is not used: the Linux console sends it as Tab.

## Pages

1. **Welcome.** What happens, and that the chosen disk is erased. Enter.
2. **Network.** Fetches `https://github.com` (`curl -fsI --max-time 6`).
   Connected: Enter. Not connected: "Connect to Wi-Fi or a network" leaves
   the UI and runs `nmtui`, then checks again; "Check again" re-checks.
   There is no way forward offline: the install downloads, and so does the
   first start.
3. **Keyboard layout.** All console keymaps (`localectl list-keymaps`, else
   the files in `/usr/share/kbd/keymaps`), `us` selected. Typing searches.
   Enter applies it with `loadkeys` at once (not in demo), so the passwords
   typed later use it.
4. **Time zone.** `timedatectl list-timezones` (else `tzdata.zi`),
   `Asia/Phnom_Penh` selected, same search.
5. **Disk.** From `lsblk`; only real, writable disks (no rom, loop, zram,
   read-only), and never the USB stick the ISO booted from (found via
   `findmnt /run/archiso/bootmnt` and its parent; if that is not mounted,
   nothing is hidden). Name, size in GB/TB, model, USB tag. Under 20 GB is
   shown dimmed as "too small" and refused with "Pick a disk of 20 GB or
   more." No disks, or lsblk failed: says so; R looks again.
6. **Encryption.** A radio pair, "No" selected. "Yes" opens a passphrase
   and its repeat, and the warning that a lost passphrase loses the files.
   Empty or different passphrases are refused below the fields.
7. **Account.** Your name (optional; no `:` or `,`), user name (filled from
   the first word of the name until edited; `^[a-z_][a-z0-9_-]{0,31}$`, not
   `root` or another system name), password twice (not empty, the same),
   computer name (`koompi`; one RFC 1123 label). Enter walks the fields;
   on the last one everything is checked and each error shows under its
   field. The account can use sudo; root stays locked.
8. **Review.** Every answer, the disk with "ERASED: everything on it is
   deleted." in red, and the time: about 10-30 minutes here, then 15-40 on
   the first start, online. The install starts only after typing the word
   `erase` and Enter; a plain Enter is refused next to the field. Esc goes
   back to change something.
9. **Install.** Writes the answers file and runs the engine. Shows
   "Step n of N" with the engine's label, a bar (a running step counts
   half), the elapsed time, and the last 10 log lines.
   - Fails (a `@@koompi fail` line or a nonzero exit): the reason, the log
     path `/var/log/koompi-install.log`, and "Try again" or "Open a shell"
     (bash; `exit` comes back). Esc goes back to Review to change answers.
   - Ctrl+C asks "Stop the install?"; Y sends SIGTERM to the engine's
     process group and shows "Stopped by you."
10. **Done.** Remove the USB stick, restart; the first start sets up the
    desktop (15-40 minutes, needs internet). "Restart now" runs
    `systemctl reboot`; "Stay in the live system" exits with code 0.

## Secrets

Passwords are drawn as `*`, kept only in fixed buffers that are zeroed on
exit and after a successful install, and reach disk only in the 0600
answers file on tmpfs, which is deleted after the engine exits.
