// Wire protocol, shell -> daemon (one command per line):
//   activate <id> <gen>   invoke the item
//   open <id> <gen>       tell the app a submenu is opening; may answer with a patch
//   close <id> <gen>      tell the app the submenu closed
//   refresh               re-resolve the focused window
//   gtk <bus> <menu_path> [app_path] [win_path]   (--test only)
//   dbusmenu <bus> <path>                          (--test only)
//   focus <pid> [address] [class]   resolve as if this Wayland window had focus (--test only)
//
// daemon -> shell:
//   {"items":[...],"gen":<n>}              the full menu for the focused window
//   {"patch":<id>,"gen":<n>,"items":[...]} replacement children for one item
//
// Ids are handed out per payload and reused, so every id-bearing command names its
// generation and is refused once that generation is replaced.
//
// globalmenu/tests/test_daemon.py is the conformance suite for this protocol
// (tests/test_globalmenu.sh builds the daemon and runs it).

use std::collections::HashSet;
use std::io::{BufRead, Write};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use koompi_globalmenu_core::compositor::{ActiveWindow, FocusSource, Hyprland};
use koompi_globalmenu_core::menu::{self, Item, Table, Target};
use koompi_globalmenu_core::{dbusmenu, gtkmenu, qtmenu, registrar, x11};

use zbus::blocking::Connection;

/// Applications register a moment after they take focus, and focus itself flaps
/// while a panel takes a grab, so both are coalesced rather than acted on.
const REFRESH_DEBOUNCE: Duration = Duration::from_millis(60);

/// A window the Qt probe has looked at is not probed again, so an application that
/// never answers costs its timeout once per window rather than on every focus
/// change. Cleared at this size; probing a window twice is harmless.
const PROBED_CAP: usize = 256;

enum Event {
    Stdin(String),
    StdinClosed,
    Focus,
    RegistrarChanged,
}

#[derive(Default)]
enum MenuSource {
    #[default]
    None,
    Gtk(gtkmenu::Source),
    DBusMenu(dbusmenu::Source),
}

fn same_source(a: &MenuSource, b: &MenuSource) -> bool {
    match (a, b) {
        (MenuSource::None, MenuSource::None) => true,
        (MenuSource::Gtk(x), MenuSource::Gtk(y)) => x.bus == y.bus && x.menu_path == y.menu_path,
        (MenuSource::DBusMenu(x), MenuSource::DBusMenu(y)) => x.bus == y.bus && x.path == y.path,
        _ => false,
    }
}

struct Daemon {
    conn: Connection,
    state: Arc<Mutex<registrar::State>>,
    table: Table,
    source: MenuSource,
    focus: Option<Hyprland>,
    /// The id space the shell is currently holding. Bumped on every full
    /// payload, never 0, so a shell that has not received one yet cannot match.
    generation: u32,
    /// Set by --test: no compositor, the shell drives the source directly.
    manual: bool,
    /// Set by `focus` under --test: the window the compositor would report.
    test_window: Option<ActiveWindow>,
    peers: qtmenu::Peers,
    /// Compositor addresses of the windows the Qt probe has looked at.
    probed: HashSet<String>,
    /// The window whose adopted menu is the current source, so a menu that has
    /// stopped answering sends that window back to the probe.
    adopted_window: Option<String>,
}

impl Daemon {
    fn emit(&mut self, items: &[Item]) {
        // A full payload replaces the table, so every id the shell was holding
        // is void from here on. Skipping 0 on wrap keeps it distinguishable
        // from a shell that has not seen a payload yet.
        self.generation = self.generation.checked_add(1).unwrap_or(1);
        write_stdout(&menu::write_json(items, self.generation));
    }

    /// Takes the requesting generation, not `self.generation`. A patch stamped with
    /// the wrong one passes the shell's staleness check and splices one application's
    /// submenu under another's.
    fn emit_patch(&self, id: u32, generation: u32, items: &[Item]) {
        write_stdout(&menu::write_patch_json(id, items, generation));
    }

    fn focused_window(&mut self) -> Option<ActiveWindow> {
        if self.manual {
            return self.test_window.clone();
        }
        self.focus.as_mut()?.active_window().ok()
    }

    /// Works out where the focused window's menu lives. Order matters: a
    /// registrar registration is the application telling us directly, and beats
    /// anything we can infer.
    fn resolve_source(&mut self) -> MenuSource {
        self.adopted_window = None;
        let Some(win) = self.focused_window() else {
            return MenuSource::None;
        };
        let Ok(pid) = u32::try_from(win.pid) else {
            return MenuSource::None;
        };
        if pid == 0 {
            return MenuSource::None;
        }

        let xid = if win.xwayland {
            x11::active_window_id()
        } else {
            None
        };

        if let Some(source) = self.registered(xid, pid) {
            return source;
        }
        if let Some(source) = xid.and_then(|id| self.source_from_x11(id)) {
            return source;
        }
        if let Some(source) = self.gtk_from_bus_name(&win.class, pid) {
            return source;
        }
        self.unregistered_qt(&win.address, pid)
    }

    fn registered(&self, xid: Option<u32>, pid: u32) -> Option<MenuSource> {
        let state = self.state.lock().ok()?;
        let entry = xid
            .and_then(|id| state.for_window(id))
            .or_else(|| state.for_pid(pid))?;
        Some(dbusmenu_source(entry))
    }

    /// A Qt menubar the application exported but never registered (`qtmenu`),
    /// adopted into the registrar table so GetMenus shows it. Probed once per
    /// window; until a window finds one, a sibling's adopted menu stands in, as
    /// the application's menu does on a Mac.
    fn unregistered_qt(&mut self, address: &str, pid: u32) -> MenuSource {
        if !self.probed.contains(address) {
            match qtmenu::find(&self.conn, &mut self.peers, pid) {
                qtmenu::Probe::Found(bus, path) => {
                    if let Ok(mut state) = self.state.lock() {
                        if state.adopt(pid, bus, path) {
                            state.persist();
                        }
                    }
                    self.mark_probed(address);
                }
                qtmenu::Probe::None => self.mark_probed(address),
                qtmenu::Probe::Empty => {}
            }
        }
        let Ok(state) = self.state.lock() else {
            return MenuSource::None;
        };
        let Some(entry) = state.adopted(pid) else {
            return MenuSource::None;
        };
        self.adopted_window = Some(address.to_owned());
        dbusmenu_source(entry)
    }

    fn mark_probed(&mut self, address: &str) {
        if self.probed.len() >= PROBED_CAP {
            self.probed.clear();
        }
        self.probed.insert(address.to_owned());
    }

    /// KDE applications point at a dbusmenu through window properties rather
    /// than registering, so both conventions come out of the same xprop call.
    fn source_from_x11(&self, xid: u32) -> Option<MenuSource> {
        let props = x11::read_props(xid);
        if props.has_kde_menu() {
            return Some(MenuSource::DBusMenu(dbusmenu::Source {
                bus: props.kde_bus?,
                path: props.kde_menu_path?,
            }));
        }
        if !props.complete() {
            return None;
        }
        Some(MenuSource::Gtk(gtkmenu::Source {
            bus: props.bus?,
            menu_path: props.menu_path?,
            app_path: props.app_path,
            win_path: props.win_path,
            unity_path: props.unity_path,
        }))
    }

    /// Native-Wayland GTK applications publish no window properties, so the
    /// only handle we have is the app id. A GApplication owns its app id as a
    /// bus name and exports its menubar under the matching object path, so a
    /// window class with a dot in it is worth one probe.
    fn gtk_from_bus_name(&self, class: &str, pid: u32) -> Option<MenuSource> {
        if !class.contains('.') || class.len() > 200 {
            return None;
        }
        if registrar::pid_of(&self.conn, class) != pid {
            return None;
        }

        let base: String = std::iter::once('/')
            .chain(class.chars().map(|c| if c == '.' || c == '-' { '/' } else { c }))
            .collect();
        let menu_path = format!("{base}/menus/menubar");
        if !self.has_gtk_menu(class, &menu_path) {
            return None;
        }

        Some(MenuSource::Gtk(gtkmenu::Source {
            bus: class.to_owned(),
            menu_path,
            app_path: Some(base.clone()),
            win_path: self.find_window_action_path(class, &base),
            unity_path: None,
        }))
    }

    fn has_gtk_menu(&self, bus: &str, path: &str) -> bool {
        let Ok(reply) = self.conn.call_method(
            Some(bus),
            path,
            Some("org.gtk.Menus"),
            "Start",
            &(&[0u32][..],),
        ) else {
            return false;
        };
        let body = reply.body();
        body.deserialize::<Vec<(u32, u32, Vec<zbus::zvariant::OwnedValue>)>>()
            .is_ok_and(|groups| !groups.is_empty())
    }

    /// Nothing says which per-window action group belongs to the focused window, so take
    /// the first that answers. Multi-window apps still get the right menu; only the win.*
    /// enabled states may come from a sibling.
    fn find_window_action_path(&self, bus: &str, base: &str) -> Option<String> {
        (1..=4).find_map(|n| {
            let path = format!("{base}/window/{n}");
            self.conn
                .call_method(Some(bus), path.as_str(), Some("org.gtk.Actions"), "DescribeAll", &())
                .ok()
                .map(|_| path)
        })
    }

    fn refresh(&mut self) {
        if !self.manual {
            let next = self.resolve_source();
            // Focus flaps: moving between two windows of the same application,
            // or a panel taking a grab, resolves to the menu already on screen.
            // Re-emitting would tear down a menu the user has open.
            if same_source(&self.source, &next) {
                return;
            }
            self.source = next;
        }
        self.publish_source();
    }

    fn publish_source(&mut self) {
        self.table.clear();
        let items = match &self.source {
            MenuSource::None => Vec::new(),
            MenuSource::Gtk(s) => gtkmenu::fetch(&self.conn, s, &mut self.table),
            MenuSource::DBusMenu(s) => dbusmenu::fetch(&self.conn, s, &mut self.table),
        };
        // an adopted menu that answers nothing is gone; its window gets probed again
        if items.is_empty() {
            if let Some(address) = self.adopted_window.take() {
                self.probed.remove(&address);
            }
        }
        self.emit(&items);
    }

    fn command(&mut self, line: &str) {
        let line = line.trim();
        let mut it = line.split_whitespace();
        let Some(verb) = it.next() else { return };
        let rest: Vec<&str> = it.collect();

        match verb {
            "activate" => {
                let Some((id, generation)) = parse_targeted(&rest) else {
                    return;
                };
                if generation != self.generation {
                    return;
                }
                self.activate(id);
            }
            "open" | "close" => {
                let Some((id, generation)) = parse_targeted(&rest) else {
                    return;
                };
                if generation != self.generation {
                    return;
                }
                self.set_open(id, generation, verb == "open");
            }
            "refresh" => self.refresh(),
            "gtk" if self.manual => {
                let (Some(bus), Some(menu_path)) = (rest.first(), rest.get(1)) else {
                    return;
                };
                self.source = MenuSource::Gtk(gtkmenu::Source {
                    bus: (*bus).to_owned(),
                    menu_path: (*menu_path).to_owned(),
                    app_path: rest.get(2).map(|s| (*s).to_owned()),
                    win_path: rest.get(3).map(|s| (*s).to_owned()),
                    unity_path: None,
                });
                self.publish_source();
            }
            "focus" if self.manual => {
                let Some(pid) = rest.first().and_then(|p| p.parse::<i64>().ok()) else {
                    return;
                };
                self.test_window = Some(ActiveWindow {
                    pid,
                    xwayland: false,
                    address: rest.get(1).map_or_else(|| format!("test:{pid}"), |a| (*a).to_owned()),
                    class: rest.get(2).map(|c| (*c).to_owned()).unwrap_or_default(),
                });
                self.source = self.resolve_source();
                self.publish_source();
            }
            "dbusmenu" if self.manual => {
                let (Some(bus), Some(path)) = (rest.first(), rest.get(1)) else {
                    return;
                };
                self.source = MenuSource::DBusMenu(dbusmenu::Source {
                    bus: (*bus).to_owned(),
                    path: (*path).to_owned(),
                });
                self.publish_source();
            }
            _ => {}
        }
    }

    fn activate(&mut self, id: u32) {
        let Some(target) = self.table.get(id) else { return };
        match target.clone() {
            Target::Gtk {
                bus,
                path,
                action,
                arg,
            } => gtkmenu::activate(&self.conn, &bus, &path, &action, arg.as_ref()),
            Target::DBusMenu { bus, path, item_id } => {
                dbusmenu::event(&self.conn, &bus, &path, item_id, "clicked")
            }
        }
    }

    /// Applications with lazily built menus only fill a submenu in when they
    /// are told it is about to show, so opening one re-reads that subtree and
    /// patches it into the shell's copy.
    fn set_open(&mut self, id: u32, generation: u32, opening: bool) {
        let Some(Target::DBusMenu { bus, path, item_id }) = self.table.get(id).cloned() else {
            return;
        };

        if !opening {
            dbusmenu::event(&self.conn, &bus, &path, item_id, "closed");
            return;
        }

        dbusmenu::event(&self.conn, &bus, &path, item_id, "opened");
        let src = dbusmenu::Source { bus, path };
        let items = dbusmenu::fetch_from(&self.conn, &src, &mut self.table, item_id);
        if !items.is_empty() {
            self.emit_patch(id, generation, &items);
        }
    }
}

/// Parses the "<id> <gen>" tail of an activate/open/close command. The
/// generation is required: an unversioned command cannot be checked for
/// staleness, and running it anyway is exactly the wrong-command-fires bug the
/// guard exists to stop, so it is refused rather than trusted.
fn parse_targeted(args: &[&str]) -> Option<(u32, u32)> {
    if args.len() != 2 {
        return None;
    }
    Some((args[0].parse().ok()?, args[1].parse().ok()?))
}

fn write_stdout(payload: &str) {
    let mut out = std::io::stdout().lock();
    let _ = out.write_all(payload.as_bytes());
    let _ = out.flush();
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let manual = std::env::args().any(|a| a == "--test");

    let conn = koompi_globalmenu_core::connect()?;
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").ok().map(Into::into);
    let state = Arc::new(Mutex::new(registrar::State::new(runtime_dir)));
    let (tx, rx) = mpsc::channel();

    registrar::publish(&conn, state.clone(), notify_sender(&tx))?;

    let focus = if manual {
        None
    } else {
        match Hyprland::from_env() {
            Ok(h) => Some(h),
            Err(e) => {
                eprintln!("global-menu: no compositor to follow: {e}");
                None
            }
        }
    };

    spawn_stdin_reader(tx.clone());
    if !manual {
        spawn_focus_reader(tx.clone());
    }

    let mut daemon = Daemon {
        conn,
        state,
        table: Table::new(),
        source: MenuSource::None,
        focus,
        generation: 0,
        manual,
        test_window: None,
        peers: qtmenu::Peers::default(),
        probed: HashSet::new(),
        adopted_window: None,
    };

    // The first payload is unconditional: the shell and the conformance suite
    // both read one before sending anything. refresh() cannot serve it, because
    // an unresolved source equals the one we start on and its focus-flap guard
    // swallows the emit.
    daemon.emit(&[]);

    // Resolving needs the compositor, so the real menu arrives on the same
    // debounced path as any other focus change rather than blocking startup.
    let mut pending: Option<Instant> =
        (!manual).then(|| Instant::now() + REFRESH_DEBOUNCE);
    loop {
        let event = match pending {
            Some(deadline) => {
                let now = Instant::now();
                if now >= deadline {
                    pending = None;
                    daemon.refresh();
                    continue;
                }
                match rx.recv_timeout(deadline - now) {
                    Ok(e) => e,
                    Err(RecvTimeoutError::Timeout) => {
                        pending = None;
                        daemon.refresh();
                        continue;
                    }
                    Err(RecvTimeoutError::Disconnected) => break,
                }
            }
            None => match rx.recv() {
                Ok(e) => e,
                Err(_) => break,
            },
        };

        match event {
            Event::Stdin(line) => daemon.command(&line),
            Event::StdinClosed => break,
            // With no compositor to ask there is nothing to re-resolve, and an
            // extra payload would only confuse whoever is driving us.
            Event::Focus | Event::RegistrarChanged if !daemon.manual => {
                pending.get_or_insert_with(|| Instant::now() + REFRESH_DEBOUNCE);
            }
            _ => {}
        }
    }
    Ok(())
}

fn dbusmenu_source(entry: &registrar::Entry) -> MenuSource {
    MenuSource::DBusMenu(dbusmenu::Source {
        bus: entry.service.clone(),
        path: entry.path.clone(),
    })
}

fn notify_sender(tx: &mpsc::Sender<Event>) -> registrar::Notify {
    let (ntx, nrx) = mpsc::channel();
    let forward = tx.clone();
    std::thread::spawn(move || {
        while nrx.recv().is_ok() {
            if forward.send(Event::RegistrarChanged).is_err() {
                return;
            }
        }
    });
    ntx
}

fn spawn_stdin_reader(tx: mpsc::Sender<Event>) {
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if tx.send(Event::Stdin(line)).is_err() {
                return;
            }
        }
        let _ = tx.send(Event::StdinClosed);
    });
}

fn spawn_focus_reader(tx: mpsc::Sender<Event>) {
    std::thread::spawn(move || {
        let Ok(mut hypr) = Hyprland::from_env() else {
            return;
        };
        while hypr.wait_for_change().is_ok() {
            if tx.send(Event::Focus).is_err() {
                return;
            }
        }
    });
}
