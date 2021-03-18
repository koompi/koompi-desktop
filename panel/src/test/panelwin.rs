use iced_wgpu::Viewport;
use iced_winit::winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    window::Window,
};
use iced_winit::Size;
pub struct WindowPanel {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    pub window: Window,
}

impl WindowPanel {
    pub fn new(win: Window) -> Self {
        let inner_size = win.inner_size();
        let position = win.outer_position().unwrap();
        Self {
            x: position.x,
            y: position.y,
            width: inner_size.width,
            height: inner_size.height,
            window: win,
        }
    }
    pub fn set_deafult_size(&mut self) {
        match self.window.primary_monitor() {
            Some(handler) => {
                let size = handler.size();
                self.window
                    .set_inner_size(PhysicalSize::new(size.width, 32));
            }
            None => {}
        }
    }
    pub fn set_outer_position(&mut self) {
        self.window.set_outer_position(PhysicalPosition::new(0, 0));
    }
    pub fn get_viewport(&self, size: PhysicalSize<u32>) -> Viewport {
        Viewport::with_physical_size(
            Size::new(size.width, size.height),
            self.window.scale_factor(),
        )
    }
    pub fn get_width(&self) -> u32 {
        self.width
    }
    pub fn get_height(&self) -> u32 {
        self.height
    }
}
