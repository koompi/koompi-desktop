use crate::styles::slider::SliderType;
use iced::{Column, Element};
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, Align, Button, Command, Container, Length, Program, Row, Slider, Text,
};
#[derive(Debug, Default)]
pub struct Audio {
    controllers: [button::State; 2],
    settings: [button::State; 4],
    value: f32,
    input_value: f32,
    slide_dev: slider::State,
    slide_head: slider::State,
    current_index: usize,
}
#[derive(Debug, Clone)]
pub enum AudioMsg {
    OnVolumeChange(f32),
    OnInputChanged(f32),
    OnSwitchView(usize),
    OnMute,
    OnAdvance,
}
impl Audio {
    pub fn new() -> Self {
        Self::default()
    }
}
use AudioMsg::*;
impl Program for Audio {
    type Message = AudioMsg;
    type Renderer = self::Renderer;
    fn update(&mut self, msg: self::AudioMsg) -> Command<AudioMsg> {
        match msg {
            OnVolumeChange(volume) => {
                self.value = volume;
            }
            OnSwitchView(index) => {
                println!("current index: {}", index);
                self.current_index = index;
            }
            OnInputChanged(volume) => {
                self.input_value = volume;
            }
            OnAdvance => {}
            OnMute => {}
        }
        Command::none()
    }
    fn view(&mut self) -> Element<Self::Message> {
        let [mute, settings, devices, apps] = &mut self.settings;
        let [device, app] = &mut self.controllers;
        let tab = Row::new()
            .width(Length::Fill)
            .align_items(Align::Center)
            .push(
                Row::new()
                    .push(
                        Button::new(device, Text::new("Device").width(Length::Fill))
                            .on_press(AudioMsg::OnSwitchView(1)),
                    )
                    .push(
                        Button::new(app, Text::new("Applications").width(Length::Fill))
                            .on_press(AudioMsg::OnSwitchView(2)),
                    ),
            );
        let content = Column::new()
            .spacing(10)
            .push(Text::new("Headphones"))
            .push(
                Slider::new(
                    &mut self.slide_dev,
                    0.0..=100.0,
                    self.value,
                    Self::Message::OnVolumeChange,
                )
                .style(SliderType::Default),
            )
            .push(Text::new("Headset Microphone"))
            .push(
                Slider::new(
                    &mut self.slide_head,
                    0.0..=100.0,
                    self.input_value,
                    AudioMsg::OnInputChanged,
                )
                .style(SliderType::Default),
            );
        Container::new(Column::new().push(tab).push(content))
            .padding(10)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x()
            .into()
    }
}
