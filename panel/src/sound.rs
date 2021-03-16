use super::controls::icon;
use super::state::CommonState;
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, Align, Button, Color, Column, Command, Container, Element, Font,
    HorizontalAlignment, Length, Program, Row, Slider, Space, Text,
};
use std::cell::RefCell;
#[derive(Debug, Default)]
pub struct Sound {
    pub slider: slider::State,
    pub value: f32,
    pub mute: button::State,
    pub kind: RefCell<ControlType>,
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
#[derive(Debug, Copy, Clone)]
pub enum ControlType {
    Monitor,
    Bell,
    Sound,
    Clipboard,
    Wifi,
    Keyboard,
}
impl Default for ControlType {
    fn default() -> Self {
        ControlType::Monitor
    }
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
        match self.kind.get_mut() {
            ControlType::Monitor => Container::new(
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
                            .on_press(SoundMsg::ButtonClicked),
                    ),
            )
            .into(),
            ControlType::Sound => Text::new("Sound").into(),
            ControlType::Clipboard => Text::new("Clipboard").into(),
            ControlType::Keyboard => Text::new("Keyboard").into(),
            ControlType::Wifi => Text::new("Wifi").into(),
            ControlType::Bell => Text::new("Bell").into(),
        }
    }
}
