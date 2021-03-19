use super::desktop_item_error::DesktopItemError;
use std::fmt::{self, Display, Formatter};
use std::str::FromStr;

const APP: &str = "Application";
const LINK: &str = "Link";
const DIR: &str = "Directory";

#[derive(Debug, Clone, Copy)]
pub enum DesktopItemType {
    APP,
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
                APP => Ok(DesktopItemType::APP),
                LINK => Ok(DesktopItemType::LINK),
                DIR => Ok(DesktopItemType::DIR),
                _ => Err(DesktopItemError::InvalidType),
            }
        }
    }
}

impl Display for DesktopItemType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}",
            match self {
                DesktopItemType::APP => APP,
                DesktopItemType::LINK => LINK,
                DesktopItemType::DIR => DIR,
                _ => "",
            }
        )
    }
}
