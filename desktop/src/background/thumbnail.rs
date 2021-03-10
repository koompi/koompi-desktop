use super::thumbnail_size::ThumbnailSize;
use super::placement::Placement;
use std::path::PathBuf;
use std::collections::HashMap;
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct Thumbnail {
    placement: Placement,
    thumbnail_size: ThumbnailSize,
    #[serde(serialize_with = "toml::ser::tables_last")]
    images: HashMap<String, PathBuf>,
}

impl Thumbnail {
    pub fn placement(&self) -> Placement {
        self.placement
    }

    pub fn thumbnail_size(&self) -> ThumbnailSize {
        self.thumbnail_size
    }

    pub fn images(&self) -> &HashMap<String, PathBuf> {
        &self.images
    }
}