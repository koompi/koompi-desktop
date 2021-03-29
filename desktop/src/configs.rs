pub mod background_conf;
pub mod desktop_item_conf;
pub mod wallpaper_conf;
mod persistent_data;

pub use persistent_data::PersistentData;
use background_conf::BackgroundConf;
use desktop_item_conf::DesktopItemConf;
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