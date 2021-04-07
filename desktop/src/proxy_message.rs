use crate::gui::{ContextMsg, DesktopMsg, BackgroundConfMsg, DesktopConfigMsg};

#[derive(Debug, Clone)]
pub enum ProxyMessage {
    Desktop(DesktopMsg),
    ContextMenu(ContextMsg),
    Bg(BackgroundConfMsg),
    DesktopConf(DesktopConfigMsg),
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

impl From<DesktopConfigMsg> for ProxyMessage {
    fn from(msg: DesktopConfigMsg) -> Self {
        Self::DesktopConf(msg)
    }
}