use crate::gui::{ContextMsg, DesktopMsg, BackgroundConfMsg};

#[derive(Debug, Clone)]
pub enum ProxyMessage {
    Desktop(DesktopMsg),
    ContextMenu(ContextMsg),
    Bg(BackgroundConfMsg),
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

impl From<BackgroundConfMsg> for ProxyMessage {
    fn from(msg: BackgroundConfMsg) -> Self {
        Self::Bg(msg)
    }
}