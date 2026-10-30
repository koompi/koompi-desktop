//! strings.zig - every word the installer shows, in one place for
//! translation later. ASCII only: the Linux console font has no Khmer.

pub const brand = "KOOMPI OS";
pub const title = "Installer";
pub const demo_badge = "DEMO - no disk is touched";

pub const steps = [_][]const u8{
    "Welcome", "Network", "Keyboard", "Time zone", "Disk", "Encryption", "Account", "Review", "Install",
};

// keys in the footer: key, then what it does
pub const k_enter = "Enter";
pub const k_esc = "Esc";
pub const k_quit = "Ctrl+C";
pub const k_arrows = "Up/Down";
pub const k_tab = "Tab";
pub const k_space = "Space";
pub const f_continue = "continue";
pub const f_choose = "choose";
pub const f_back = "back";
pub const f_quit = "quit";
pub const f_move = "move";
pub const f_type = "type to search";
pub const f_field = "next field";
pub const f_toggle = "on/off";

pub const too_small = "Make the window at least 80x24.";

pub const welcome_h = "Install KOOMPI on this computer";
pub const welcome_lines = [_][]const u8{
    "You will pick a disk, make an account,",
    "and the rest runs by itself.",
    "",
    "The disk you pick is erased completely.",
    "Back up anything you need from it first.",
};
pub const welcome_needs = "You need: internet, a disk of 20 GB or more.";

pub const net_h = "Internet";
pub const net_checking = "Checking the connection...";
pub const net_online = "Connected.";
pub const net_offline = "Not connected.";
pub const net_why = "Needed for the install, and again on the first start.";
pub const net_connect = "Connect to Wi-Fi or a network";
pub const net_retry = "Check again";
pub const net_continue_needs = "Connect first: the install cannot run offline.";

pub const kb_h = "Keyboard layout";
pub const tz_h = "Time zone";
pub const search = "Search:";
pub const no_match = "Nothing matches. Backspace to edit the search.";

pub const disk_h = "Install on which disk?";
pub const disk_erase = "Everything on the chosen disk is erased.";
pub const disk_none = "No disk to install on was found.";
pub const disk_rescan = "Press R to look again.";
pub const disk_small = "too small";
pub const disk_need = "Pick a disk of 20 GB or more.";
pub const disk_usb = "USB";
pub const disk_probe_failed = "Could not list the disks.";

pub const enc_h = "Encrypt the disk?";
pub const enc_toggle = "Encrypt";
pub const enc_on = "On";
pub const enc_off = "Off";
pub const enc_why = "Asked at every start. Forget it and your files are gone.";
pub const enc_pass = "Passphrase";
pub const enc_again = "Again";

pub const acct_h = "Your account";
pub const acct_name = "Your name";
pub const acct_user = "User name";
pub const acct_pass = "Password";
pub const acct_again = "Again";
pub const acct_host = "Computer name";
pub const acct_sudo = "This account can run admin tasks (sudo).";

pub const rev_h = "Ready to install";
pub const rev_disk = "Disk";
pub const rev_erase = "ERASED: everything on it is deleted.";
pub const rev_enc = "Encryption";
pub const rev_user = "Account";
pub const rev_host = "Computer";
pub const rev_kb = "Keyboard";
pub const rev_tz = "Time zone";
pub const rev_time1 = "Takes about 10-30 minutes. Then the first start sets";
pub const rev_time2 = "up the desktop: 15-40 minutes more, online.";
pub const rev_confirm = "Type erase and press Enter:";
pub const rev_confirm_word = "erase";
pub const rev_confirm_wrong = "Type the word erase to start.";

pub const inst_h = "Installing KOOMPI";
pub const inst_starting = "Starting...";
pub const inst_keep_on = "Keep the computer on and plugged in.";
pub const inst_step = "Step";
pub const inst_of = "of";
pub const inst_failed_h = "The install did not finish";
pub const inst_log_at = "Full log:";
pub const inst_log_path = "/var/log/koompi-install.log";
pub const inst_retry = "Try again";
pub const inst_shell = "Open a shell (type exit to come back)";
pub const inst_no_engine = "The install program is missing:";
pub const inst_exit_code = "The install stopped with code";
pub const inst_stopped = "Stopped by you.";
pub const inst_answers_failed = "Could not save the answers to";
pub const inst_stop_q = "Stop the install?";
pub const inst_stop_q2 = "The disk is left unusable until you install again.";
pub const inst_stop_keys = "Y stop   N keep going";

pub const done_h = "KOOMPI is installed";
pub const done_lines = [_][]const u8{
    "1. Remove the USB stick.",
    "2. Restart.",
    "",
    "On its first start KOOMPI sets up the desktop.",
    "That takes 15-40 minutes and needs the internet.",
};
pub const done_reboot = "Restart now";
pub const done_stay = "Stay in the live system";
pub const done_reboot_failed = "Restart failed. Run: systemctl reboot";

pub const quit_q = "Quit the installer? Nothing has been changed.";
pub const quit_q_after = "Quit the installer?";
pub const quit_keys = "Y quit   N stay";

pub const shell_note = "Type exit to return to the installer.";
