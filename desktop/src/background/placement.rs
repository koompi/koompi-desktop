use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
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