pub mod background_conf;
pub mod desktop_item_conf;
mod persistent_data;
pub mod wallpaper_conf;

use background_conf::BackgroundConf;
use desktop_item_conf::DesktopItemConf;
pub use persistent_data::PersistentData;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

const DESKTOP_CONF: &str = "desktop.toml";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DesktopConf {
    #[serde(rename = "Background")]
    pub background_conf: BackgroundConf,
    #[serde(rename = "Desktop_Entry")]
    pub desktop_item_conf: DesktopItemConf,
}

impl PersistentData for DesktopConf {
    fn relative_path() -> PathBuf {
        PathBuf::from("desktop").join(DESKTOP_CONF)
    }
}

impl DesktopConf {
    pub fn background_conf(&self) -> &BackgroundConf {
        &self.background_conf
    }

    pub fn desktop_item_conf(&self) -> &DesktopItemConf {
        &self.desktop_item_conf
    }
}
