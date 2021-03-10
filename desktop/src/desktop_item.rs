mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_error;

use super::constants::{TYPE, DESKTOP_ENTRY, ICON, NAME, COMMENT};
use std::path::{PathBuf, Path};
use std::time::Duration;
use std::str::FromStr;
use std::convert::From;
use desktop_item_type::DesktopItemType;
pub use desktop_item_error::DesktopItemError;
use freedesktop_entry_parser::{Entry, parse_entry, AttrSelector};

pub struct DesktopItem {
    pub entry: Entry,
    path: PathBuf,
    entry_type: DesktopItemType,
    modified: bool,
    launch_time: Duration
}

impl DesktopItem {
    pub fn from_file<P: AsRef<Path>>(file: P) -> Result<Self, DesktopItemError> {
        if file.as_ref().exists() && file.as_ref().is_file() {
            if let Some(extension) = file.as_ref().extension() {
                if extension.eq("desktop") {
                    let entry = parse_entry(file.as_ref())?;
                    let entry_type = DesktopItemType::from_str(entry.section(DESKTOP_ENTRY).attr(TYPE).unwrap_or(""))?;
                    
                    Ok(Self {
                        entry,
                        path: PathBuf::from(file.as_ref()),
                        entry_type,
                        modified: false,
                        launch_time: Duration::from_secs(0)
                    })
                } else {
                    Err(DesktopItemError::InvalidType)
                }
            } else {
                Err(DesktopItemError::InvalidType)
            }
            
        } else {
            Err(DesktopItemError::NoFilename {
                name: file.as_ref().display().to_string()
            })
        }
        
    }

    pub fn path(&self) -> &PathBuf {
        &self.path
    }

    fn desktop_entry(&self) -> AttrSelector<&str> {
        self.entry.section(DESKTOP_ENTRY)
    }

    pub fn name(&self) -> Option<String> {
        self.desktop_entry().attr(NAME).map(ToString::to_string)
    }

    pub fn comment(&self) -> Option<String> {
        self.desktop_entry().attr(COMMENT).map(ToString::to_string)
    }

    pub fn icon(&self) -> PathBuf {
        self.desktop_entry().attr(ICON).map(|name| {
            if Path::new(name).is_absolute() {
                PathBuf::from(name)
            } else {
                let path = PathBuf::from("/usr/share/icons/hicolor/scalable/apps").join(format!("{}.svg", name));
                if path.exists() {
                    path
                } else {
                    let path = PathBuf::from("/usr/share/icons/hicolor/128x128/apps").join(format!("{}.png", name));
                    if path.exists() {
                        path
                    } else {
                        PathBuf::from("/usr/share/icons/koompi.svg")
                    }
                }
            }
        }).unwrap_or(PathBuf::new())
    }
}