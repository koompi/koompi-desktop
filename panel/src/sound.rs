use super::controls::icon;
use super::state::CommonState;
use crate::styles::buttonstyle::buttons::ButtonStyle::Transparent as btnzero;
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, Align, Button, Color, Column, Command, Container, Element, Font,
    HorizontalAlignment, Length, Program, Row, Slider, Space, Text,
};

#[derive(Debug, Default)]
pub struct Sound {
    slider: slider::State,
    value: f32,
    mute: button::State,
}
impl CommonState for Sound {
    fn get_name(&self) -> String {
        String::from("Sound View")
    }
}
#[derive(Debug, Clone)]
pub enum SoundMsg {
    SoundChanged(f32),
    ButtonClicked,
}

impl Sound {
    pub fn new() -> Self {
        Self::default()
    }
}

impl Program for Sound {
    type Renderer = Renderer;
    type Message = SoundMsg;

    fn update(&mut self, msg: SoundMsg) -> Command<SoundMsg> {
        match msg {
            SoundMsg::SoundChanged(val) => {
                self.value = val;
            }
            SoundMsg::ButtonClicked => {
                println!("Hello World");
            }
        }
        Command::none()
    }
    fn view(&mut self) -> Element<SoundMsg, Renderer> {
        Container::new(
            Column::new()
                .align_items(Align::Center)
                .push(Text::new("Speaker"))
                .push(Space::with_width(Length::Fill))
                .push(
                    Row::new()
                        .align_items(Align::Center)
                        .push(icon('\u{f028}'))
                        .push(Slider::new(
                            &mut self.slider,
                            0.0..=100.0,
                            self.value,
                            SoundMsg::SoundChanged,
                        ))
                        .push(Text::new(self.value.to_string())),
                )
                .push(
                    Button::new(&mut self.mute, Text::new("Mute Sound"))
                        .style(btnzero)
                        .on_press(SoundMsg::ButtonClicked),
                ),
        )
        .into()
    }
}
