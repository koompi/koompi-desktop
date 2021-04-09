use crate::views::{applets::AppletsMsg, panel::Message};

#[derive(Debug, Clone)]
pub enum ProxyMessage {
    DesktopPanel(Message),
    PopupMenu(AppletsMsg),
}

impl From<Message> for ProxyMessage {
    fn from(msg: Message) -> Self {
        Self::DesktopPanel(msg)
    }
}

impl From<AppletsMsg> for ProxyMessage {
    fn from(msg: AppletsMsg) -> Self {
        Self::PopupMenu(msg)
    }
}
