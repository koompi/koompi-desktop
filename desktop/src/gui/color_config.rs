use iced_wgpu::Renderer;
use iced_winit::{text_input, Align, Color, Element, Row, Text, TextInput};

#[derive(Debug, Clone)]
pub struct ColorConfigUI {
    color_state: text_input::State,
    text: String,
    color: Color,
}

#[derive(Debug, Clone)]
pub enum ColorConfigMsg {
    ColorChanged(String),
}

impl ColorConfigUI {
    pub fn new(color: Color) -> Self {
        Self {
            color,
            text: String::from("sample test"),
            color_state: text_input::State::new(),
        }
    }

    pub fn update(&mut self, msg: ColorConfigMsg) {
        match msg {
            ColorConfigMsg::ColorChanged(val) => self.text = val,
        }
    }

    pub fn view(&mut self) -> Element<ColorConfigMsg, Renderer> {
        let lb_color = Text::new("Color: ");
        let txt_color = TextInput::new(
            &mut self.color_state,
            "",
            &self.text,
            ColorConfigMsg::ColorChanged,
        )
        .padding(7);
        Row::new()
            .spacing(15)
            .align_items(Align::Center)
            .push(lb_color)
            .push(txt_color)
            .into()
    }
}
