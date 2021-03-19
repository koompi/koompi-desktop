use std::path::PathBuf;
use serde::{Serialize, Deserialize};
use std::fmt::{self, Display, Formatter};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WallpaperConf {
    pub placement: Placement,
    pub wallpaper_path: PathBuf,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Placement {
    Tiled,
    Zoomed,
    Centered,
    Scaled,
    FillScreen,
    Spanned,
}

impl Default for Placement {
    fn default() -> Self {
        Self::FillScreen
    }
}

impl Placement {
    pub const ALL: [Placement; 6] = [
        Placement::Tiled, Placement::Zoomed, Placement::Centered, Placement::Scaled, Placement::FillScreen, Placement::Spanned
    ];
}

impl Display for Placement {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result { 
        use Placement::*;
        write!(f, "{}", match self {
            Tiled => "Tiled",
            Zoomed => "Zoomed",
            Centered => "Centered",
            Scaled => "Scaled",
            FillScreen => "FillScreen",
            Spanned => "Spanned"
        })
    }
}
