use thiserror::Error;
use super::desktop_item::DesktopItemError;
use super::background::WallpaperError;

#[derive(Error, Debug)]
pub enum DesktopError {
    #[error("Config file not found: {0}")]
    ConfigNotFound(String),
    #[error(transparent)]
    ParseConfigError(#[from] toml::de::Error),
    #[error(transparent)]
    ParseStringError(#[from] toml::ser::Error),
    #[error(transparent)]
    DesktopItemError(#[from] DesktopItemError),
    #[error(transparent)]
    WallpaperError(#[from] WallpaperError),
    #[error(transparent)]
    IOError(#[from] std::io::Error),
}   