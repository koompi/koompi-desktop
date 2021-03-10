use super::thumbnail::Thumbnail;
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", content = "args")]
pub enum WallpaperType {
    Color(String),
    Image(Thumbnail),
}

impl Default for WallpaperType {
    fn default() -> Self {
        Self::Color(String::from("#000000"))
    }
}