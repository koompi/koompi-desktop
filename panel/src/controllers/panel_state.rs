use super::common::*;
use crate::views::{controls::Controls, controls::Message};
pub struct PanelState {
    pub window: Window,
    popup_x: u32,
    pub state: RefCell<State<Controls>>,
}

impl PanelState {
    pub fn setup(event_loop: &EventLoop<()>, instance: &wgpu::Instance) -> Self {
        // let event_proxy = event_loop.create_proxy();
        let panel = WindowBuilder::new()
            .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 32, 0])])
            .with_x11_window_type(vec![XWindowType::Dock])
            .build(&event_loop)
            .unwrap();
        let (applets, _) = Controls::new(());
        let context_state = block_on(State::new(&panel, applets, Some(&setttings(20))));
        let mut popup_x = 0;
        if let Some(display) = panel.primary_monitor() {
            let width = display.size().width;
            panel.set_inner_size(PhysicalSize::new(width, 32));
            popup_x = width - 400;
        }
        panel.set_outer_position(PhysicalPosition::new(0, 0));
        Self {
            window: panel,
            popup_x,
            state: RefCell::new(context_state),
        }
    }
    pub fn instance(self) -> Window {
        self.window
    }
    pub fn state(&self) -> &RefCell<State<Controls>> {
        &self.state
    }
}

pub fn setttings(text_size: u16) -> Settings {
    Settings {
        default_text_size: text_size,
        ..Settings::default()
    }
}
