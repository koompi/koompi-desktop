use iced::{Column, Element};
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, Align, Button, Command, Container, Length, Program, Row, Slider, Text,
};
#[derive(Debug, Default)]
pub struct Audio {
    controllers: Vec<(String, button::State)>,
    settings: [button::State; 4],
    value: f32,
    slide_dev: slider::State,
    current_index: usize,
}
#[derive(Debug, Clone)]
pub enum AudioMsg {
    OnVolumeChange(f32),
    OnSwitchView(usize),
    OnMute,
    OnAdvance,
}
impl Audio {
    pub fn new() -> Self {
        let controllers = vec![
            ("Devices".to_owned(), button::State::new()),
            ("Applications".to_owned(), button::State::new()),
        ];
        Self {
            controllers,
            ..Self::default()
        }
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
            OnAdvance => {}
            OnMute => {}
        }
        Command::none()
    }
    fn view(&mut self) -> Element<Self::Message> {
        let [mute, settings, devices, apps] = &mut self.settings;
        let tab = Row::new().align_items(Align::Center).push(
            Row::new()
                .push(Button::new(devices, Text::new("Device")))
                .push(Button::new(apps, Text::new("Applications")))
                .push(
                    Row::new()
                        .push(Button::new(mute, Text::new("Mute")).on_press(Self::Message::OnMute))
                        .push(
                            Button::new(settings, Text::new("Settings"))
                                .on_press(Self::Message::OnAdvance),
                        ),
                ),
        );
        let content = Column::new().push(Slider::new(
            &mut self.slide_dev,
            0.0..=100.0,
            self.value,
            Self::Message::OnVolumeChange,
        ));
        Container::new(Column::new().push(tab).push(content)).into()
    }
}
