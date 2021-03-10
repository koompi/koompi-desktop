use crate::background::wallpaper_type::WallpaperType;
use serde::{Serialize, Deserialize};

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct BackgroundConf {
    wallpaper_type: WallpaperType
}

impl BackgroundConf {
    pub fn wallpaper_type(&self) -> &WallpaperType {
        &self.wallpaper_type
    }
}