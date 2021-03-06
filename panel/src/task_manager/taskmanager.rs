use std::any::Any;
use std::collections::HashMap;
use std::error::Error;
use x11rb::connection::Connection;
use x11rb::protocol::xproto::{Atom, AtomEnum, ConnectionExt, GetPropertyReply, Window};
use x11rb::x11_utils::TryParse;
use x11rb::xcb_ffi::XCBConnection;

pub struct TaskManager {
    window_id: Window,
    window_class: Option<String>,
    window_instance: Option<String>,
    window_name: Option<String>,
}
fn find_active_window(
    conn: &impl Connection,
    root: Window,
    net_active_window: Atom,
    hash_map: &mut HashMap<&str, Option<Window>>,
) -> Result<(Window, bool), Box<dyn Error>> {
    let window: Window = AtomEnum::ANY.into();
    let active_window = conn
        .get_property(false, root, net_active_window, window, 0, 1)?
        .reply()?;
    if active_window.format == 32 && active_window.length == 1 {
        // Things will be so much easier with the next release:
        let widnow_id = u32::try_parse(&active_window.value)?.0;
        let focus_changed = widnow_id != hash_map["xid"].unwrap();
        hash_map.insert("xid", Some(widnow_id));
        Ok((u32::try_parse(&active_window.value)?.0, focus_changed))
    } else {
        // Query the input focus
        Ok((conn.get_input_focus()?.reply()?.focus, false))
    }
}
fn parse_string_property(property: &GetPropertyReply) -> &str {
    std::str::from_utf8(&property.value).unwrap_or("Invalid utf8")
}
fn parse_wm_class(property: &GetPropertyReply) -> (&str, &str) {
    if property.format != 8 {
        return (
            "Malformed property: wrong format",
            "Malformed property: wrong format",
        );
    }
    let value = &property.value;
    // The property should contain two null-terminated strings. Find them.
    if let Some(middle) = value.iter().position(|&b| b == 0) {
        let (instance, class) = value.split_at(middle);
        // Skip the null byte at the beginning
        let mut class = &class[1..];
        // Remove the last null byte from the class, if it is there.
        if class.last() == Some(&0) {
            class = &class[..class.len() - 1];
        }
        let instance = std::str::from_utf8(instance);
        let class = std::str::from_utf8(class);
        (
            instance.unwrap_or("Invalid utf8"),
            class.unwrap_or("Invalid utf8"),
        )
    } else {
        ("Missing null byte", "Missing null byte")
    }
}
impl TaskManager {
    pub fn new() -> Result<(), Box<dyn Error>> {
        let mut last_seen = HashMap::new();
        last_seen.insert("xid", Some(10000000));
        // Set up our state
        let (conn, screen) = XCBConnection::connect(None)?;
        let root = conn.setup().roots[screen].root;
        let net_activate_win = conn.intern_atom(false, b"_NET_ACTIVE_WINDOW").unwrap();
        let net_wm_name = conn.intern_atom(false, b"_NET_WM_NAME").unwrap();
        let utf8_string = conn.intern_atom(false, b"UTF8_STRING").unwrap();
        let net_activate_win = net_activate_win.reply().unwrap().atom;
        let net_wm_name = net_wm_name.reply().unwrap().atom;
        let utf8_string = utf8_string.reply().unwrap().atom;
        let (focus, _) = find_active_window(&conn, root, net_activate_win, &mut last_seen)?;
        println!("XID {:?}", focus);
        // Collect the replies to the atoms
        let (net_wm_name, utf8_string) = (net_wm_name, utf8_string);
        let (wm_class, string): (AtomEnum, AtomEnum) =
            (AtomEnum::WM_CLASS.into(), AtomEnum::STRING.into());
        // Get the property from the window that we need
        let name =
            conn.get_property(false, focus, net_wm_name, utf8_string, 0, u32::max_value())?;
        let class = conn.get_property(false, focus, wm_class, string, 0, u32::max_value())?;
        let (name, class) = (name.reply()?, class.reply()?);7j
        println!("Window name: {:?}", parse_string_property(&name));
        let (instance, class) = parse_wm_class(&class);
        println!("Window instance: {:?}", instance);
        println!("Window class: {:?}", class);
        // Print out the result
        // loop {
        //     let (win, changed) = find_active_window(&conn, root, net_activate_win, &mut last_seen)?;
        //     if changed {
        //         println!("Window name: {:?}", parse_string_property(&name));
        //         let (instance, class) = parse_wm_class(&class);
        //         println!("Window instance: {:?}", instance);
        //         println!("Window class: {:?}", class);
        //     } else {
        //         loop {}
        //     }
        // }
        Ok(())
    }
}
