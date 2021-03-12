mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_load_flags;
mod desktop_item_launch_flags;
mod desktop_item_icon_flags;
mod desktop_item_error;
mod encoding;

use desktop_item_status::DesktopItemStatus;
use desktop_item_type::DesktopItemType;
use desktop_item_load_flags::DesktopItemLoadFlags;
use desktop_item_launch_flags::DesktopItemLaunchFlags;
use desktop_item_error::DesktopItemError;
use std::path::Path;
use std::collections::HashMap;
use std::time::Duration;
use version_compare::Version;
use regex::Regex;
use freedesktop_entry_parser::{Entry, parse_entry};

const TYPE: &str = "Type";

// #[derive(Debug, Clone, Copy)]
// pub struct DesktopItem {
//     encoding: String,
//     version: Version,
//     name: String,
//     generic_name: Option<String>,
//     path: Path,
//     item_type: DesktopItemType,
//     file_pattern: Regex,
//     try_exec: Option<String>,
//     exec: String,
//     no_display: bool,
//     comment: String,
//     actions: String,
//     icon: String,
//     mini_icon: Option<String>,
//     hidden: bool,
//     read_only: bool,
//     only_show_in: String,
//     categories: String,
//     mime_type: Regex,
//     terminal: bool,
// }

#[derive(Debug, Clone)]
pub struct DesktopItem {
    entry: Entry,
    path: Path,
    entry_type: DesktopItemType,
    modified: bool,
    languages: Vec<String>,
    launch_time: Duration
}

impl DesktopItem {
    pub fn from_file<P: AsRef<Path>>(file: P, flags: DesktopItemLoadFlags) -> Result<Self, DesktopItemError> {
        let entry = parse_entry(file)?;
        let entry_type = DesktopItemType::from_str(entry.section("Desktop Entry").attr(TYPE)?)?;

        Self {
            entry,
            path: file,
            entry_type,
            modified: false,
            languages: Vec::new(),
            launch_time: Duration::zero()
        }
    }

    pub fn from_uri<S: Into<String>>(uri: S, flags: DesktopItemLoadFlags) -> Self {

    }

    pub fn from_string<S: Into<String>>(uri: S, s: S, size: usize, flags: DesktopItemLoadFlags) -> Self {

    }

    pub fn from_basename<S: Into<String>>(basename: S, flags: DesktopItemLoadFlags) -> Self {

    }

    pub fn save<S: Into<String>>(&mut self, under: S, force: bool) -> bool {

    }

    pub fn launch<P: AsRef<Path>>(&self, file_list: Vec<P>, flags: DesktopItemLaunchFlags) -> i16 {

    }

    pub fn launch_with_env<P: AsRef<Path>>(&self, file_list: Vec<P>, flags: DesktopItemLaunchFlags, env: String) -> i16 {

    }

    pub fn launch_on_workspace<P: AsRef<Path>>(&self, file_list: Vec<P>, flags: DesktopItemLaunchFlags, workspace: u8) -> i16 {

    }

    pub fn drop_uri_list<S: Into<String>>(&self, uri_list: Vec<S>, flags: DesktopItemLaunchFlags) -> i16 {

    }

    pub fn drop_uri_list_with_env<S: Into<String>>(&self, uri_list: Vec<S>, flags: DesktopItemLaunchFlags, env: String) -> i16 {

    }

    pub fn exists(&self) -> bool {

    }

    pub fn entry_type(&self) -> DesktopItemType {

    }

    pub fn set_entry_type(&mut self, entry_type: DesktopItemType) {

    }

    pub fn path(&self) -> Path {

    }

    pub fn set_path<P: AsRef<Path>>(&mut self, path: P) {

    }

    pub fn status(&self) -> DesktopItemStatus {

    }

    pub fn icon(&self) -> String {

    }

    pub fn find_icon<S: Into<String>>(icon: S, desired_size: u16, flags: u8) -> String {

    }

    pub fn attr_exists<S: Into<String>>(&self, attr: S) -> bool {

    }

    pub fn set_launch_time(&mut self, timestamp: Duration) {

    } 
}

impl DesktopItem {
    fn get_string<S: Into<String>>(&self, attr: S) -> String {

    }

    fn set_string<S: Into<String>>(&mut self, attr: S, val: S) {

    }

    fn get_strings<S: Into<String>>(&self, attr: S) -> Vec<String> {

    }

    fn set_strings<S: Into<String>>(&mut self, attr: S, vals: Vec<S>) {

    }

    fn get_bool<S: Into<String>>(&self, attr: S) -> bool {

    }

    fn set_bool<S: Into<String>>(&mut self, attr: S, val: bool) {

    }
}