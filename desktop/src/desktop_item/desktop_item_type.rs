use std::str::FromStr;
use std::fmt::{self, Display, Formatter};
use crate::constants::{APP, DIR, LINK};
use super::desktop_item_error::DesktopItemError;
use super::desktop_entry::DesktopEntry;

#[derive(Debug, Clone)]
pub enum DesktopItemType {
    APP(DesktopEntry),
    LINK,
    DIR,
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
                _ => Err(DesktopItemError::InvalidType)
            }
        }
    }
}

impl Display for DesktopItemType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", match self {
            DesktopItemType::APP(_) => APP,
            DesktopItemType::LINK => LINK,
            DesktopItemType::DIR => DIR,
            _ => ""
        })
    }
}