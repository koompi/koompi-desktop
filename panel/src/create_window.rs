use crate::views::panel::Message;
use iced_winit::winit;
use winit::event_loop::EventLoop;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowBuilder},
};
#[allow(dead_code)]
#[derive(Debug)]
pub enum WinType {
    Panel(([u64; 4], Option<(u32, u32)>)),
    Dock(Option<(u32, u32)>),
    Menu(Option<(u32, u32)>),
    Dialog(Option<(u32, u32)>),
}
#[derive(Debug)]
pub struct NewWindow {
    window: Window,
    size: PhysicalSize<u32>,
    position: PhysicalPosition<i32>,
    is_visible: bool,
    kind: WinType,
}
impl NewWindow {
    pub fn instance(self) -> Window {
        self.window
    }
    pub fn new(event_loop: &EventLoop<Message>, kind: WinType) -> Self {
        let window = match kind {
            WinType::Panel((reserve_size, pos)) => {
                let win = WindowBuilder::new()
                    // .with_inner_size(PhysicalSize::new(1920, 40))
                    .with_x11_window_strut(vec![XWindowStrut::Strut(reserve_size)])
                    .with_x11_window_type(vec![XWindowType::Dock])
                    .build(&event_loop)
                    .unwrap();
                match pos {
                    Some((x, y)) => {
                        win.set_outer_position(PhysicalPosition::new(x, y));
                        win
                    }
                    None => win,
                }
            }
            WinType::Dock(size) => {
                let win = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Dock])
                    .with_visible(false)
                    .build(&event_loop)
                    .unwrap();
                match size {
                    Some((w, h)) => {
                        win.set_inner_size(PhysicalSize::new(w, h));
                        win
                    }
                    None => win,
                }
            }
            WinType::Menu(size) => {
                let win = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Menu])
                    .with_decorations(false)
                    .with_always_on_top(true)
                    .with_visible(false)
                    .build(&event_loop)
                    .unwrap();
                match size {
                    Some((w, h)) => {
                        win.set_inner_size(PhysicalSize::new(w, h));
                        win
                    }
                    None => win,
                }
            }
            WinType::Dialog(size) => {
                let win = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::PopupMenu])
                    .with_visible(false)
                    .build(&event_loop)
                    .unwrap();
                match size {
                    Some((w, h)) => {
                        win.set_inner_size(PhysicalSize::new(w, h));
                        win
                    }
                    None => win,
                }
            }
        };
        let size = window.inner_size();
        let position = window.outer_position().unwrap();
        Self {
            window,
            size,
            position,
            is_visible: true,
            kind,
        }
    }
}
