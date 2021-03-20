use std::fmt::{self, Display, Formatter};
use serde::{Serialize, Deserialize};
use super::wallpaper_conf::WallpaperConf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackgroundConf {
    pub kind: BackgroundType,
    pub color_background: String,
    #[serde(rename = "Wallpaper_Config")]
    pub wallpaper_conf: WallpaperConf,
}

impl Default for BackgroundConf {
    fn default() -> Self {
        Self {
            kind: BackgroundType::Color,
            color_background: String::from("#272727"),
            wallpaper_conf: WallpaperConf::default(),
        }
    }
}


#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BackgroundType {
    Color,
    Wallpaper
}

impl BackgroundType {
    pub const ALL: [BackgroundType; 2] = [
        BackgroundType::Color, BackgroundType::Wallpaper
    ];  
}

impl Display for BackgroundType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        use BackgroundType::*;
        write!(f, "{}", match self {
            Color => "Color",
            Wallpaper => "Wallpaper"
        })
    }
}