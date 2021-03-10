use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct ThumbnailSize {
    pub width: u32,
    pub height: u32,
}

impl Default for ThumbnailSize {
    fn default() -> Self {
        Self {
            width: 100,
            height: 60,
        }
    }
}