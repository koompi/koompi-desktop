mod desktop;
mod context_menu;
mod desktop_config;
mod background_config;
mod styles;

pub use desktop::{Desktop, DesktopMsg};
pub use context_menu::{ContextMenu, ContextMsg};
pub use desktop_config::{DesktopConfigUI, DesktopConfigMsg};
pub use background_config::{BackgroundConfigUI, BackgroundConfMsg};