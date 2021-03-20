mod desktop_item_status;
mod desktop_item_type;
mod desktop_item_error;

use super::constants::{TYPE, DESKTOP_ENTRY, ICON, NAME, COMMENT, EXEC};
use std::path::{PathBuf, Path};
use std::time::Duration;
use std::str::FromStr;
use std::convert::From;
use std::process::Command;
use desktop_item_type::DesktopItemType;
use desktop_item_status::DesktopItemStatus;
pub use desktop_item_error::DesktopItemError;

#[derive(Debug, Clone, Default)]
pub struct DesktopItem {
    pub path: PathBuf,
    pub name: Option<String>,
    pub comment: Option<String>,
    exec: Option<String>,
    pub icon_path: Option<PathBuf>,
    entry_type: DesktopItemType,
    launch_time: Duration,
    status: DesktopItemStatus,
}

impl DesktopItem {
    pub fn from_file<P: AsRef<Path>>(file: P) -> Result<Self, DesktopItemError> {
        if file.as_ref().exists() {
            if file.as_ref().is_file() {
                if let Some(extension) = file.as_ref().extension() {
                    if extension.eq("desktop") {
                        let entry = freedesktop_entry_parser::parse_entry(file.as_ref())?;
                        let desktop_entry = entry.section(DESKTOP_ENTRY);
                        let name = desktop_entry.attr(NAME).map(ToString::to_string);
                        let comment = desktop_entry.attr(COMMENT).map(ToString::to_string);
                        let exec = desktop_entry.attr(EXEC).map(ToString::to_string);
                        let entry_type = DesktopItemType::from_str(desktop_entry.attr(TYPE).unwrap_or(""))?;
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
                        Ok(Self {
                            path: PathBuf::from(file.as_ref()),
                            name, comment, entry_type, icon_path, exec,
                            ..Self::default()
                        })
                    } else {
                        Err(DesktopItemError::InvalidType)
                    }
                } else {
                    Err(DesktopItemError::InvalidType)
                }
            } else if file.as_ref().is_dir() {
                let entry_type = DesktopItemType::DIR;

                Ok(Self {
                    path: PathBuf::from(file.as_ref()),
                    name: file.as_ref().file_name().map(|n| n.to_str().map(ToString::to_string).unwrap()),
                    entry_type,
                    ..Self::default()
                })
            } else {
                Err(DesktopItemError::InvalidType)
            }  
        } else {
            Err(DesktopItemError::NoFilename {
                name: file.as_ref().display().to_string()
            })
        }
        
    }

    // pub fn path(&self) -> &PathBuf {
    //     &self.path
    // }

    // pub fn name(&self) -> Option<&String> {
    //     self.name.as_ref()
    // }

    // pub fn comment(&self) -> Option<&String> {
    //     self.comment.as_ref()
    // }

    // pub fn icon(&self) -> Option<&PathBuf> {
    //     self.icon_path.as_ref()
    // }

    pub fn handle_exec(&mut self) {
        match self.entry_type {
            DesktopItemType::APP => {
                if let Some(exec) = &self.exec {
                    println!("{}", exec);
                    Command::new(exec).spawn().expect("failed to execute application");
                }
            },
            _ => {}
        }
    }
}