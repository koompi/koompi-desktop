use iced_wgpu::{
    Renderer
};
use iced_winit::{
    text_input, Element, Text, TextInput, Row, Align,
};

#[derive(Debug, Clone, Default)]
pub struct ColorConfigUI {
    color_state: text_input::State,
    color: String,
}

#[derive(Debug, Clone)]
pub enum ColorConfigMsg {
    ColorChanged(String)
}

impl ColorConfigUI {
    pub fn new(color: String) -> Self {
        Self {
            color, ..Self::default()
        }
    }

    pub fn update(&mut self, msg: ColorConfigMsg) {
        match msg {
            ColorConfigMsg::ColorChanged(val) => self.color = val
        }
    }

    pub fn view(&mut self) -> Element<ColorConfigMsg, Renderer> {
        let lb_color = Text::new("Color: ");
        let txt_color = TextInput::new(&mut self.color_state, "", &self.color, ColorConfigMsg::ColorChanged).padding(7);
        Row::new().spacing(15).align_items(Align::Center)
            .push(lb_color)
            .push(txt_color)
            .into()
    }
}

