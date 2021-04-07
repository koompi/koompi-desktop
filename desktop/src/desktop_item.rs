mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_error;
mod desktop_entry;

use super::constants::{TYPE, DESKTOP_ENTRY, ICON, NAME, COMMENT, DEFAULT_APPS, MIME_FILE, MIME_INFO_CACHE, MIME_CACHE, INODE_DIR};
use std::path::{PathBuf, Path};
use std::str::FromStr;
use std::convert::From;
use desktop_item_type::DesktopItemType;
use desktop_item_status::DesktopItemStatus;
use desktop_entry::DesktopEntry;
pub use desktop_item_error::DesktopItemError;
use lazy_static::lazy_static;
const APPS_DIR: &str = "applications";
lazy_static! {
    static ref SYS_DIR: PathBuf = PathBuf::from("/usr/share").join(APPS_DIR);
    static ref SYS_LOCAL_DIR: PathBuf = PathBuf::from("/usr/local/share").join(APPS_DIR);
    static ref LOCAL_DIR: PathBuf = dirs_next::data_dir().unwrap().join(APPS_DIR);
    static ref CONF_DIR: PathBuf = dirs_next::config_dir().unwrap();
}

#[derive(Debug, Clone, Default)]
pub struct DesktopItem {
    pub path: PathBuf,
    pub name: Option<String>,
    pub icon_path: Option<PathBuf>,
    pub comment: Option<String>,
    entry_type: DesktopItemType,
    status: DesktopItemStatus,
}

impl DesktopItem {
    pub fn new<P: AsRef<Path>>(file: P) -> Result<Self, DesktopItemError> {
        let file = file.as_ref();
        let mut res = false;
        let mut desktop_item = Self {
            path: file.to_path_buf(),
            name: file.file_name().map(|name| name.to_str().unwrap().to_string()),
            ..Self::default()
        };

        if file.exists() {
            if file.is_file() {
                if let Some(extension) = file.extension() {
                    if extension.eq("desktop") {
                        let entry = freedesktop_entry_parser::parse_entry(file)?;
                        let desktop_entry = entry.section(DESKTOP_ENTRY);
                        let name = desktop_entry.attr(NAME).map(ToString::to_string);
                        let comment = desktop_entry.attr(COMMENT).map(ToString::to_string);
                        let mut entry_type = DesktopItemType::from_str(desktop_entry.attr(TYPE).unwrap_or(""))?;
                        if let DesktopItemType::APP(entry) = &mut entry_type {
                            *entry = DesktopEntry::new(&desktop_entry);
                        }
                        let icon_path = desktop_entry.attr(ICON).map(|name| {
                            if Path::new(name).is_absolute() {
                                PathBuf::from(name)
                            } else {
                                let path = PathBuf::from("/usr/share/icons/hicolor/scalable/apps").join(format!("{}.svg", name));
                                if path.exists() {
                                    path
                                } else {
                                    walkdir::WalkDir::new("/usr/share/icons").follow_links(true).into_iter().filter_map(|e| e.ok())
                                        .find(|entry| entry.path().file_stem().unwrap().to_str().unwrap() == name.split('.').collect::<Vec<&str>>()[0])
                                        .map(|entry| entry.into_path())
                                        .unwrap_or(PathBuf::from("/usr/share/icons/koompi.svg"))
                                }
                            }
                        });

                        desktop_item = Self {
                            path: file.to_path_buf(),
                            entry_type, name, icon_path, comment, 
                            ..Self::default()
                        };
                    } else {
                        desktop_item.entry_type = DesktopItemType::FILE;
                        desktop_item.icon_path = Some(PathBuf::from("/usr/share/icons/koompi.svg"));
                    }
                    res = true;
                }
            } else if file.is_dir() {
                desktop_item.entry_type = DesktopItemType::DIR;
                desktop_item.icon_path = Some(PathBuf::from("/usr/share/icons/koompi.svg"));
                res = true;
            } 

            if res {
                Ok(desktop_item)
            } else {
                Err(DesktopItemError::InvalidType)
            }
        } else {
            Err(DesktopItemError::NoFilename (file.display().to_string()))
        }
    }

    pub fn handle_exec(&self) -> Result<(), DesktopItemError> {
        match &self.entry_type {
            DesktopItemType::APP(entry) => entry.handle_exec(None),
            DesktopItemType::DIR | DesktopItemType::FILE => {
                let mut res = false;
                let mime_type = mime_guess::from_path(self.path.to_path_buf());
                let mime_type = mime_type.first_raw().unwrap_or(INODE_DIR);

                let mut config = configparser::ini::Ini::new();
                let _ = config.load(CONF_DIR.join(MIME_FILE).to_str().unwrap());
                let apps = if let Some(apps) = config.get(DEFAULT_APPS, mime_type) {
                    Some(apps.to_string())
                } else {
                    let _ = config.load(LOCAL_DIR.join(MIME_INFO_CACHE).to_str().unwrap());
                    if let Some(apps) = config.get(MIME_CACHE, mime_type) {
                        Some(apps.to_string())
                    } else {
                        let _ = config.load(SYS_DIR.join(MIME_INFO_CACHE).to_str().unwrap());
                        config.get(MIME_CACHE, mime_type)
                    }
                }; 
                
                if let Some(apps) = apps {
                    let mut splitted_apps = apps.split(';');
                    while let Some(app) = splitted_apps.next() {
                        let mut app_path = LOCAL_DIR.join(app);
                        if !app_path.exists() {
                            app_path = SYS_LOCAL_DIR.join(app);
                            if !app_path.exists() {
                                app_path = SYS_DIR.join(app);
                            }
                        }
                        
                        let entry = freedesktop_entry_parser::parse_entry(app_path)?;
                        let desktop_entry = entry.section(DESKTOP_ENTRY);
                        let entry = DesktopEntry::new(&desktop_entry);
                        if let Ok(()) = entry.handle_exec(self.path.to_str()) {
                            res = true;
                            break;
                        }
                    }
                }
                
                if res {
                    Ok(())
                } else {
                    Err(DesktopItemError::NoExecString)
                }
            },
            _ => Err(DesktopItemError::InvalidType)
        }
    }
}