#[derive(Debug, Clone, Copy)]
pub enum DesktopItemStatus {
    UNCHANGED = 0,
    CHANGED = 1,
}

impl Default for DesktopItemStatus {
    fn default() -> Self {
        Self::UNCHANGED
    }
}
