mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_error;
mod desktop_entry;

use super::constants::{DATA_DIRS, TYPE, DESKTOP_ENTRY, NAME, COMMENT, MIME_TYPE, DEFAULT_APPS, ADDED_ASSOCS, REM_ASSOCS, MIME_FILE, MIME_INFO_CACHE, MIME_CACHE, INODE_DIR};
use crate::configs::{Resources, Config};
use std::path::{PathBuf, Path};
use std::str::FromStr;
use std::convert::From;
use std::time::SystemTime;
use std::collections::HashSet;
pub use desktop_item_type::DesktopItemType;
use desktop_item_status::DesktopItemStatus;
use desktop_entry::DesktopEntry;
pub use desktop_item_error::DesktopItemError;

const APPS_DIR: &str = "applications";

#[derive(Debug, Clone, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct DesktopItem {
    pub path: PathBuf,
    pub name: Option<String>,
    pub icon_path: Option<PathBuf>,
    pub comment: Option<String>,
    pub entry_type: DesktopItemType,
    pub status: DesktopItemStatus,
    pub modified: Option<SystemTime>,
    pub created: Option<SystemTime>,
}

impl DesktopItem {
    pub fn new<P: AsRef<Path>>(path: P, icon_path: Option<PathBuf>) -> Result<Self, DesktopItemError> {
        let path = path.as_ref();
        let mut desktop_item = Self {
            path: path.to_path_buf(),
            name: path.file_name().map(|name| name.to_str().unwrap().to_string()),
            icon_path,
            ..Self::default()
        };

        if path.exists() {
            let metadata = path.metadata()?;
            let file_type = metadata.file_type();
            desktop_item.modified = metadata.modified().ok();
            desktop_item.created = metadata.created().ok();
            desktop_item.entry_type = DesktopItemType::from(file_type);
            
            if file_type.is_file() {
                if let Some(extension) = path.extension() {
                    if extension.eq("desktop") {
                        let entry = freedesktop_entry_parser::parse_entry(path)?;
                        let desktop_entry = entry.section(DESKTOP_ENTRY);
                        let name = desktop_entry.attr(NAME).map(ToString::to_string);
                        let comment = desktop_entry.attr(COMMENT).map(ToString::to_string);
                        let mut entry_type = DesktopItemType::from_str(desktop_entry.attr(TYPE).unwrap_or(""))?;
                        if let DesktopItemType::APP(entry) = &mut entry_type {
                            *entry = DesktopEntry::new(&desktop_entry);
                        }

                        desktop_item.name = name;
                        desktop_item.comment = comment;
                        desktop_item.entry_type = entry_type;
                    }
                }
            }

            Ok(desktop_item)
        } else {
            Err(DesktopItemError::NoFilename (path.display().to_string()))
        }
    }

    pub fn default_app(&self) -> Option<DesktopEntry> {
        match &self.entry_type {
            DesktopItemType::APP(entry) => Some(entry.to_owned()),
            DesktopItemType::DIR | DesktopItemType::FILE | DesktopItemType::LINK => {
                let path = if let DesktopItemType::LINK = self.entry_type {
                    self.path.read_link().ok()
                } else {
                    Some(self.path.to_path_buf())
                };

                if let Some(path) = path {
                    let mime_guess = mime_guess::from_path(path);
                    let mime_type = if let DesktopItemType::DIR = self.entry_type {
                        INODE_DIR.to_string()
                    } else {
                        mime_guess.first_or_octet_stream().to_string()
                    };

                    let apps: HashSet<_> = MimeAppsConfig.find_values(DEFAULT_APPS, &mime_type).join(";").split(';').map(ToOwned::to_owned).collect();
                    apps.into_iter().find_map(|app| {
                        let mut res = None;

                        if let Some(app_path) = ApplicationResource.find_path_exists(app) {
                            let entry = freedesktop_entry_parser::parse_entry(app_path).unwrap();
                            let desktop_entry = entry.section(DESKTOP_ENTRY);
                            if let Some(mime_types) = desktop_entry.attr(MIME_TYPE) {
                                if mime_types.split(';').any(|mime| mime == mime_type) {
                                    res = Some(DesktopEntry::new(&desktop_entry));
                                }
                            }
                        }
                        res
                    }).or_else(|| {
                        let cache: HashSet<_> = MimeCacheConfig.find_values(MIME_CACHE, &mime_type).join(";").split(';').map(ToOwned::to_owned).collect();
                        cache.into_iter().find_map(|app| {
                            let mut res = None;
    
                            if let Some(app_path) = ApplicationResource.find_path_exists(app) {
                                let entry = freedesktop_entry_parser::parse_entry(app_path).unwrap();
                                let desktop_entry = entry.section(DESKTOP_ENTRY);
                                if let Some(mime_types) = desktop_entry.attr(MIME_TYPE) {
                                    if mime_types.split(';').any(|mime| mime == mime_type) {
                                        res = Some(DesktopEntry::new(&desktop_entry));
                                    }
                                }
                            }
                            res
                        })
                    })
                } else {
                    None
                }
            }
        }
    }

    pub fn prefered_apps(&self) -> Vec<DesktopEntry> {
        let mut res = Vec::new();

        match &self.entry_type {
            DesktopItemType::APP(entry) => res.push(entry.to_owned()),
            DesktopItemType::DIR | DesktopItemType::FILE | DesktopItemType::LINK => {
                let path = if let DesktopItemType::LINK = self.entry_type {
                    self.path.read_link().ok()
                } else {
                    Some(self.path.to_path_buf())
                };

                if let Some(path) = path {
                    let mime_guess = mime_guess::from_path(path);
                    let mime_type = if let DesktopItemType::DIR = self.entry_type {
                        INODE_DIR.to_string()
                    } else {
                        mime_guess.first_or_octet_stream().to_string()
                    };
                    println!("{:?}", mime_type);
                    
                    let blacklist: HashSet<_> = MimeAppsConfig.find_values(REM_ASSOCS, &mime_type).join(";").split(';').map(ToOwned::to_owned).collect();
                    let mut added = MimeAppsConfig.find_values(ADDED_ASSOCS, &mime_type);
                    added.extend(MimeCacheConfig.find_values(MIME_CACHE, &mime_type));
                    let apps: HashSet<_> = added.join(";").split(';').map(ToOwned::to_owned).collect();
                    let filtered_apps: Vec<_> = apps.into_iter().filter(|app| blacklist.contains(app)).collect();
    
                    res.extend(filtered_apps.into_iter().filter_map(|app| {
                        let mut res = None;

                        if let Some(app_path) = ApplicationResource.find_path_exists(app) {
                            let entry = freedesktop_entry_parser::parse_entry(app_path).unwrap();
                            let desktop_entry = entry.section(DESKTOP_ENTRY);
                            if let Some(mime_types) = desktop_entry.attr(MIME_TYPE) {
                                if mime_types.split(';').any(|mime| mime == mime_type) {
                                    res = Some(DesktopEntry::new(&desktop_entry));
                                }
                            }
                        }
                        res
                    }));
                }
            },
        }
        res
    }

    pub fn handle_exec(&self, prefer_app_idx: Option<usize>) -> Result<(), DesktopItemError> {
        match &self.entry_type {
            DesktopItemType::APP(entry) => entry.handle_exec(None),
            DesktopItemType::DIR | DesktopItemType::FILE | DesktopItemType::LINK => {
                let path = if let DesktopItemType::LINK = self.entry_type {
                    self.path.read_link()?
                } else {
                    self.path.to_path_buf()
                };
                
                if let Some(app_idx) = prefer_app_idx {
                    if let Some(entry) = self.prefered_apps().get(app_idx) {
                        entry.handle_exec(path.to_str())?
                    }
                } else if let Some(entry) = self.default_app() {
                    entry.handle_exec(path.to_str())?
                }

                Ok(())
            }
        }
    }
}

pub struct ApplicationResource;
impl Resources for ApplicationResource {
    fn relative_path() -> PathBuf {
        PathBuf::from(APPS_DIR)
    }

    fn additional_paths() -> Option<Vec<PathBuf>> {
        let current_de = std::env::var("XDG_CURRENT_DESKTOP");
        current_de.map(|de| Self::base_paths().into_iter().map(|path| path.join(APPS_DIR).join(de.as_str())).collect()).ok()
    }
}

pub struct MimeAppsConfig;
impl Config for MimeAppsConfig {
    fn config_file() -> PathBuf {
        PathBuf::from(MIME_FILE)
    }

    fn additional_base_paths() -> Option<Vec<PathBuf>> {
        Some(DATA_DIRS.iter().map(|path| path.join(APPS_DIR)).collect())
    }
}

pub struct MimeCacheConfig;
impl Config for MimeCacheConfig {
    fn config_file() -> PathBuf {
        PathBuf::from(MIME_INFO_CACHE)
    }

    fn additional_base_paths() -> Option<Vec<PathBuf>> {
        Some(DATA_DIRS.iter().map(|path| path.join(APPS_DIR)).collect())
    }
}