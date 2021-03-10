mod background_conf;
mod desktop_item_conf;

use background_conf::BackgroundConf;
use desktop_item_conf::DesktopItemConf;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::fs;
use super::errors::DesktopError;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct DesktopConf {
    background_conf: BackgroundConf,
    desktop_item_conf: DesktopItemConf,
}

impl DesktopConf {
    pub fn new<P: AsRef<Path>>(file: P) -> Result<Self, DesktopError> {
        if file.as_ref().exists() && file.as_ref().is_file() {
            Ok(toml::from_str(&fs::read_to_string(file)?)?)
        } else {
            let default = DesktopConf::default();
            let toml = toml::to_string_pretty(&default)?;
            if let Some(parent) = file.as_ref().parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(file.as_ref(), toml)?;
            Ok(default)
            // Err(DesktopError::ConfigNotFound(file.as_ref().display().to_string()))
        }
    }

    pub fn background_conf(&self) -> &BackgroundConf {
        &self.background_conf
    }

    pub fn desktop_item_conf(&self) -> &DesktopItemConf {
        &self.desktop_item_conf
    }
}