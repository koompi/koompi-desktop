use crate::background::wallpaper_type::WallpaperType;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BackgroundConf {
    wallpaper_type: WallpaperType,
}

impl BackgroundConf {
    pub fn wallpaper_type(&self) -> &WallpaperType {
        &self.wallpaper_type
    }
}
