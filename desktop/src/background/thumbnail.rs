use super::placement::Placement;
use super::thumbnail_size::ThumbnailSize;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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
