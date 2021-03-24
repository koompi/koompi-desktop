use super::common::icon;
use super::monitor::{Monitor, MonitorMsg};
use super::sound::{Audio, AudioMsg};
use crate::styles::containers::CustomContainer;
use iced_wgpu::Renderer;
use iced_winit::{button, slider, Command, Element, Program, Text};
use std::cell::RefCell;
#[derive(Debug, Default)]
pub struct Applets {
    pub slider: slider::State,
    pub value: f32,
    pub mute: button::State,
    pub kind: RefCell<ControlType>,
    monitor: Monitor,
    audio: Audio,
    pub is_shown: bool,
}
#[derive(Debug, Clone)]
pub enum AppletsMsg {
    SoundChanged(f32),
    ButtonClicked,
    MonitorMsg(MonitorMsg),
    AudioMsg(AudioMsg),
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

impl Applets {
    pub fn new() -> Self {
        Self::default()
    }
}

impl Program for Applets {
    type Renderer = Renderer;
    type Message = AppletsMsg;

    fn update(&mut self, msg: AppletsMsg) -> Command<AppletsMsg> {
        match msg {
            AppletsMsg::SoundChanged(val) => {
                self.value = val;
            }
            AppletsMsg::ButtonClicked => {
                println!("Hello World");
            }
            AppletsMsg::MonitorMsg(msg) => {
                self.monitor.update(msg);
            }
            AppletsMsg::AudioMsg(msg) => {
                self.audio.update(msg);
            }
        }
        Command::none()
    }
    fn view(&mut self) -> Element<AppletsMsg, Renderer> {
        match self.kind.get_mut() {
            ControlType::Monitor => self.monitor.view().map(|msg| AppletsMsg::MonitorMsg(msg)),
            ControlType::Sound => self.audio.view().map(|msg| AppletsMsg::AudioMsg(msg)),
            ControlType::Clipboard => Text::new("Clipboard").into(),
            ControlType::Keyboard => Text::new("Keyboard").into(),
            ControlType::Wifi => Text::new("Wifi").into(),
            ControlType::Bell => Text::new("Bell").into(),
        }
    }
}
