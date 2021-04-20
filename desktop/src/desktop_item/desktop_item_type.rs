use std::str::FromStr;
use std::fmt::{self, Display, Formatter};
use std::fs::FileType;
use crate::constants::{APP, DIR, LINK, FILE};
use super::desktop_item_error::DesktopItemError;
use super::desktop_entry::DesktopEntry;

#[derive(Debug, Clone, Eq, Ord, PartialEq, PartialOrd)]
pub enum DesktopItemType {
    APP(DesktopEntry),
    DIR,
    FILE,
    LINK,
    NULL,
}

impl Default for DesktopItemType {
    fn default() -> Self {
        Self::NULL
    }
}

impl FromStr for DesktopItemType {
    type Err = DesktopItemError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if s.is_empty() {
            Ok(DesktopItemType::NULL)
        } else {
            match s {
                APP => Ok(DesktopItemType::APP(DesktopEntry::default())),
                LINK => Ok(DesktopItemType::LINK),
                DIR => Ok(DesktopItemType::DIR),
                FILE => Ok(DesktopItemType::FILE),
                _ => Err(DesktopItemError::InvalidType)
            }
        }
    }
}

impl From<FileType> for DesktopItemType {
    fn from(file_type: FileType) -> Self { 
        if file_type.is_file() {
            DesktopItemType::FILE
        } else if file_type.is_dir() {
            DesktopItemType::DIR
        } else if file_type.is_symlink() {
            DesktopItemType::LINK
        } else {
            DesktopItemType::default()
        }
    }
}

impl Display for DesktopItemType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", match self {
            DesktopItemType::APP(_) => APP,
            DesktopItemType::LINK => LINK,
            DesktopItemType::DIR => DIR,
            DesktopItemType::FILE => FILE,
            _ => ""
        })
    }
}