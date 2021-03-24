use super::common::*;
use crate::views::{applets::Applets, controls::Message};
pub struct MenuState {
    pub window: Window,
    pub state: RefCell<State<Applets>>,
}

impl MenuState {
    pub fn setup(event_loop: &EventLoop<()>, instance: &wgpu::Instance) -> Self {
        let menu = WindowBuilder::new()
            .with_x11_window_type(vec![XWindowType::Dock])
            .with_inner_size(PhysicalSize::new(400, 200))
            .with_visible(false)
            .build(&event_loop)
            .unwrap();
        let (applets, _) = Applets::new(());
        let mut context_state = block_on(State::new(&menu, applets, Some(&setttings(20))));
        Self {
            window: menu,
            state: RefCell::new(context_state),
        }
    }
    pub fn instance(self) -> Window {
        self.window
    }
    pub fn state(&self) -> &RefCell<State<Applets>> {
        &self.state
    }
}

pub fn setttings(text_size: u16) -> Settings {
    Settings {
        default_text_size: text_size,
        ..Settings::default()
    }
}
