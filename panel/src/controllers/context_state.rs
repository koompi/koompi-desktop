use super::common::*;
use crate::views::{context_menu::ContexMenu, controls::Message};

pub struct ContextWindowState {
    pub window: Window,
    pub state: RefCell<State<ContexMenu>>,
}

impl ContextWindowState {
    pub fn setup(event_loop: &EventLoop<()>, instance: &wgpu::Instance) -> Self {
        let context_menu = WindowBuilder::new()
            .with_x11_window_type(vec![XWindowType::Dock])
            .with_inner_size(PhysicalSize::new(400, 200))
            .with_visible(false)
            .build(&event_loop)
            .unwrap();
        let (context_instance, _) = ContexMenu::new(());
        let mut context_state = block_on(State::new(
            &context_menu,
            context_instance,
            Some(&setttings(20)),
        ));
        Self {
            window: context_menu,
            state: RefCell::new(context_state),
        }
    }
    pub fn instance(self) -> Window {
        self.window
    }
    pub fn state(&self) -> &RefCell<State<ContexMenu>> {
        &self.state
    }
}

pub fn setttings(text_size: u16) -> Settings {
    Settings {
        default_text_size: text_size,
        ..Settings::default()
    }
}
