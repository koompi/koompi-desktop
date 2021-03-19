#[derive(Debug, Clone, Copy)]
pub enum DesktopItemStatus {
    UNCHANGED = 0,
    CHANGED = 1,
    DISAPPEARED = 2,
}

impl Default for DesktopItemStatus {
    fn default() -> Self {
        Self::UNCHANGED
    }
}