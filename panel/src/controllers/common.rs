pub use crate::window_state::State;
pub use futures::executor::block_on;
pub use iced_wgpu::{wgpu, Settings};
pub use iced_winit::{winit, Application, Program};
pub use std::cell::RefCell;
pub use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event_loop::EventLoop,
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowBuilder},
};
