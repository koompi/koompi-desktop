use super::thumbnail::Thumbnail;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", content = "value")]
pub enum WallpaperType {
    Color(String),
    Image(Thumbnail),
}

impl Default for WallpaperType {
    fn default() -> Self {
        Self::Color(String::from("#000000"))
    }
}