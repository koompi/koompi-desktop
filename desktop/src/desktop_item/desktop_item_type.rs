use std::str::FromStr;
use std::fmt::{self, Display, Formatter};
use super::desktop_item_error::DesktopItemError;

const APP: &str = "Aplication";
const LINK: &str = "Link";
const FSDEVICE: &str = "FSDevice";
const MIME_TYPE: &str = "MimeType";
const DIR: &str = "Directory";
const SERVICE: &str = "Service";
const SERVICE_TYPE: &str = "ServiceType";

#[derive(Debug, Clone, Copy)]
pub enum DesktopItemType {
    NULL = 0, // This means its NULL, that is, not set
    APP,
    LINK,
    FSDEVICE,
    MIME_TYPE,
    DIR,
    SERVICE,
    SERVICE_TYPE,
    OTHER,
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
            Some(DesktopItemType::NULL)
        } else {
            Some(match s {
                APP => DesktopItemType::APP,
                LINK => DesktopItemType::LINK,
                FSDEVICE => DesktopItemType::FSDEVICE,
                MIME_TYPE => DesktopItemType::MIME_TYPE,
                DIR => DesktopItemType::DIR,
                SERVICE => DesktopItemType::SERVICE,
                SERVICE_TYPE => DesktopItemType::SERVICE_TYPE,
                _ => DesktopItemType::OTHER
            })
        }
    }
}

impl Display for DesktopItemType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", match self {
            DesktopItemType::APP => APP,
            DesktopItemType::LINK => LINK,
            DesktopItemType::FSDEVICE => FSDEVICE,
            DesktopItemType::MIME_TYPE => MIME_TYPE,
            DesktopItemType::DIR => DIR,
            DesktopItemType::SERVICE => SERVICE,
            DesktopItemType::SERVICE_TYPE => SERVICE_TYPE,
            _ => ""
        })
    }
}