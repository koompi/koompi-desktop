// Qt menubars nobody registered.
//
// Qt 6.10 and later call RegisterWindow only when the platform is xcb
// (qdbusmenubar.cpp, registerMenuBar). On Wayland a QMenuBar still exports itself
// as com.canonical.dbusmenu at /MenuBar/<n> on the application's session
// connection, and hides the menubar inside its window, but it announces the menu
// through org_kde_kwin_appmenu, a KDE Wayland protocol Hyprland does not speak.
// Without this lookup a Wayland Qt application has no menus anywhere, and a daemon
// restart that loses its registrar table loses an X11 one's too.
//
// The lookup goes by process. Hyprland names the focused window's pid and the bus
// names each connection's pid. Qt numbers menubars from one process-wide counter,
// so the highest number is the newest window's. The tray icon's menu sits at
// /MenuBar itself, on a connection of its own, and is never taken for a menubar.

use std::collections::{HashMap, HashSet};

use zbus::blocking::fdo::DBusProxy;
use zbus::blocking::Connection;
use zbus::names::BusName;
use zbus::zvariant::OwnedValue;

pub const MENUBAR_ROOT: &str = "/MenuBar";

/// Unique bus name to pid, kept between lookups, so a lookup costs one ListNames
/// plus a pid query for each connection that appeared since the last one.
#[derive(Debug, Default)]
pub struct Peers {
    pids: HashMap<String, u32>,
}

impl Peers {
    pub fn connections_of(&mut self, conn: &Connection, pid: u32) -> Vec<String> {
        let Ok(proxy) = DBusProxy::new(conn) else {
            return Vec::new();
        };
        let Ok(names) = proxy.list_names() else {
            return Vec::new();
        };
        let unique: HashSet<String> = names
            .iter()
            .map(|n| n.to_string())
            .filter(|n| n.starts_with(':'))
            .collect();
        self.pids.retain(|name, _| unique.contains(name));
        for name in unique {
            if self.pids.contains_key(&name) {
                continue;
            }
            let owner = BusName::try_from(name.as_str())
                .ok()
                .and_then(|bus| proxy.get_connection_unix_process_id(bus).ok())
                .unwrap_or(0);
            self.pids.insert(name, owner);
        }
        let mut found: Vec<String> = self
            .pids
            .iter()
            .filter(|(_, owner)| **owner == pid)
            .map(|(name, _)| name.clone())
            .collect();
        found.sort();
        found
    }
}

#[derive(Debug, PartialEq)]
pub enum Probe {
    /// (bus, path) of the newest menubar that has something in it.
    Found(String, String),
    /// Menubars are exported but all empty so far; worth asking again later.
    Empty,
    /// The process exports no menubar.
    None,
}

pub fn find(conn: &Connection, peers: &mut Peers, pid: u32) -> Probe {
    let mut candidates: Vec<(u32, String)> = Vec::new();
    for service in peers.connections_of(conn, pid) {
        let Some(xml) = introspect(conn, &service, MENUBAR_ROOT) else {
            continue;
        };
        candidates.extend(
            menubar_numbers(&xml)
                .into_iter()
                .map(|n| (n, service.clone())),
        );
    }
    if candidates.is_empty() {
        return Probe::None;
    }
    candidates.sort_unstable_by_key(|c| std::cmp::Reverse(c.0));
    candidates
        .into_iter()
        .map(|(n, service)| (service, format!("{MENUBAR_ROOT}/{n}")))
        .find(|(service, path)| has_items(conn, service, path))
        .map_or(Probe::Empty, |(service, path)| Probe::Found(service, path))
}

/// Qt's menubar numbers among the child nodes of an Introspect reply, newest first.
pub fn menubar_numbers(xml: &str) -> Vec<u32> {
    let mut numbers: Vec<u32> = child_nodes(xml).filter_map(|n| n.parse().ok()).collect();
    numbers.sort_unstable_by(|a, b| b.cmp(a));
    numbers.dedup();
    numbers
}

fn child_nodes(xml: &str) -> impl Iterator<Item = &str> {
    xml.match_indices("<node").filter_map(move |(at, _)| {
        let tag = &xml[at + "<node".len()..];
        let tag = &tag[..tag.find('>')?];
        let value = tag.trim_start().strip_prefix("name=")?;
        let quote = value.chars().next().filter(|c| *c == '"' || *c == '\'')?;
        let value = &value[1..];
        Some(&value[..value.find(quote)?])
    })
}

fn introspect(conn: &Connection, service: &str, path: &str) -> Option<String> {
    let reply = conn
        .call_method(
            Some(service),
            path,
            Some("org.freedesktop.DBus.Introspectable"),
            "Introspect",
            &(),
        )
        .ok()?;
    reply.body().deserialize::<String>().ok()
}

fn has_items(conn: &Connection, service: &str, path: &str) -> bool {
    let Ok(reply) = conn.call_method(
        Some(service),
        path,
        Some("com.canonical.dbusmenu"),
        "GetLayout",
        &(0i32, 1i32, &["visible"][..]),
    ) else {
        return false;
    };
    let body = reply.body();
    body.deserialize::<(u32, (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>))>()
        .is_ok_and(|(_, (_, _, children))| !children.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    // What Qt answers for Introspect on /MenuBar of a process with two windows.
    const QT_REPLY: &str = r#"<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <node name="1"/>
  <node name="12"/>
  <node name="3"/>
</node>
"#;

    #[test]
    fn menubar_numbers_are_newest_first() {
        assert_eq!(menubar_numbers(QT_REPLY), vec![12, 3, 1]);
    }

    #[test]
    fn the_root_node_and_non_numeric_children_are_not_menubars() {
        let xml = "<node><interface name=\"com.canonical.dbusmenu\"/>\
                   <node name='7'/><node name=\"StatusNotifierItem\"/><node name=\"x9\"/></node>";
        assert_eq!(menubar_numbers(xml), vec![7]);
    }

    #[test]
    fn no_children_means_no_menubar() {
        assert!(menubar_numbers("<node></node>").is_empty());
        assert!(menubar_numbers("").is_empty());
        assert!(menubar_numbers("<node name=\"5").is_empty());
    }
}
