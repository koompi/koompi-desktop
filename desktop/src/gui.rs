mod background_config;
mod color_config;
mod context_menu;
mod desktop;
mod desktop_config;
mod has_changed;
mod styles;

pub use background_config::{BackgroundConfMsg, BackgroundConfigUI};
pub use context_menu::{ContextMenu, ContextMsg};
pub use desktop::{Desktop, DesktopMsg};
pub use desktop_config::{DesktopConfigMsg, DesktopConfigUI};
pub use has_changed::HasChanged;
