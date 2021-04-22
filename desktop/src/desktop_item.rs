mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_error;
mod desktop_entry;

use super::constants::{DATA_DIRS, TYPE, DESKTOP_ENTRY, NAME, COMMENT, DEFAULT_APPS, MIME_FILE, MIME_INFO_CACHE, MIME_CACHE, INODE_DIR};
use crate::configs::{Resources, Config};
use std::path::{PathBuf, Path};
use std::str::FromStr;
use std::convert::From;
use std::time::SystemTime;
pub use desktop_item_type::DesktopItemType;
use desktop_item_status::DesktopItemStatus;
use desktop_entry::DesktopEntry;
pub use desktop_item_error::DesktopItemError;

const APPS_DIR: &str = "applications";

#[derive(Debug, Clone, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct DesktopItem {
    pub path: PathBuf,
    pub name: Option<String>,
    pub icon_paths: Vec<PathBuf>,
    pub comment: Option<String>,
    pub entry_type: DesktopItemType,
    pub status: DesktopItemStatus,
    pub modified: Option<SystemTime>,
    pub created: Option<SystemTime>,
}

impl DesktopItem {
    pub fn new<P: AsRef<Path>>(path: P, icon_paths: Vec<PathBuf>) -> Result<Self, DesktopItemError> {
        let path = path.as_ref();
        let mut desktop_item = Self {
            path: path.to_path_buf(),
            name: path.file_name().map(|name| name.to_str().unwrap().to_string()),
            icon_paths,
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

    pub fn ls_prefered_apps(&self) -> Vec<DesktopEntry> {
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
                    
                    let mut apps = Vec::new();
                    if let Some(apps_str) = MimeAppsConfig.find_value(DEFAULT_APPS, &mime_type) {
                        apps.extend(apps_str.split(';').map(ToOwned::to_owned).collect::<Vec<String>>());
                    } 
                    if let Some(apps_str) = MimeCacheConfig.find_value(MIME_CACHE, &mime_type) {
                        apps.extend(apps_str.split(';').map(ToOwned::to_owned).collect::<Vec<String>>());
                    }
                    apps.dedup();
                    
                    // !FIXME: inconvenient solution
                    /* 
                        let mime_type = mime_type.first_raw().unwrap_or(INODE_DIR);
    
                        
                        let mut config = configparser::ini::Ini::new();
                        let _ = config.load(CONF_DIR.join(MIME_FILE).to_str().unwrap());
                        let apps = if let Some(apps) = config.get(DEFAULT_APPS, &mime_type) {
                            Some(apps.to_string())
                        } else {
                            let _ = config.load(LOCAL_DIR.join(MIME_INFO_CACHE).to_str().unwrap());
                            if let Some(apps) = config.get(MIME_CACHE, &mime_type) {
                                Some(apps.to_string())
                            } else {
                                let _ = config.load(SYS_DIR.join(MIME_INFO_CACHE).to_str().unwrap());
                                config.get(MIME_CACHE, &mime_type)
                            }
                        }; 
                    */
    
                    res.extend(apps.into_iter().filter_map(|app| {
                        ApplicationResource.find_path_exists(app).map(|app_path| {
                            let entry = freedesktop_entry_parser::parse_entry(app_path).unwrap();
                            let desktop_entry = entry.section(DESKTOP_ENTRY);
                            DesktopEntry::new(&desktop_entry)
                        })
                    }))
                }
            },
            _ => {}
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

                if let Some(entry) = self.ls_prefered_apps().get(prefer_app_idx.unwrap_or(0)) {
                    entry.handle_exec(path.to_str())?
                }

                Ok(())
            },
            _ => Err(DesktopItemError::InvalidType)
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