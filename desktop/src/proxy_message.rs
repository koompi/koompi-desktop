use crate::gui::{ContextMsg, DesktopMsg};

#[derive(Debug, Clone)]
pub enum ProxyMessage {
    Desktop(DesktopMsg),
    ContextMenu(ContextMsg),
}

impl From<DesktopMsg> for ProxyMessage {
    fn from(msg: DesktopMsg) -> Self { 
        Self::Desktop(msg)
    }
}

impl From<ContextMsg> for ProxyMessage {
    fn from(msg: ContextMsg) -> Self {
        Self::ContextMenu(msg)
    }
}