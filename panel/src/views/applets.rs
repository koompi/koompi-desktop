use super::battery::{BatteryView, BatteryViewMsg};
use super::common::icon;
use super::monitor::{Monitor, MonitorMsg};
use super::sound::{Audio, AudioMsg};
use crate::styles::containers::CustomContainer;
use iced_wgpu::Renderer;
use iced_winit::{button, slider, Application, Command, Container, Element, Length, Program, Text};
#[derive(Debug)]
pub struct Applets {
    pub slider: slider::State,
    pub value: f32,
    pub mute: button::State,
    pub kind: ControlType,
    monitor: Monitor,
    audio: Audio,
    battery: BatteryView,
}
#[derive(Debug, Clone)]
pub enum AppletsMsg {
    SoundChanged(f32),
    ButtonClicked,
    MonitorMsg(MonitorMsg),
    AudioMsg(AudioMsg),
    BatteryViewMsg(BatteryViewMsg),
    SwitchView(ControlType),
    BatteryTimer,
}
#[derive(Debug, Copy, Clone, PartialEq)]
pub enum ControlType {
    Monitor,
    Sound,
    Battery,
    Wifi,
    Default,
}
impl Default for ControlType {
    fn default() -> Self {
        ControlType::Monitor
    }
}

impl Applets {
    pub fn new() -> Self {
        Self {
            battery: BatteryView::new(()).0,
            audio: Audio::new(),
            monitor: Monitor::new(),
            kind: ControlType::Monitor,
            mute: button::State::new(),
            value: 0.0,
            slider: slider::State::new(),
        }
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
            AppletsMsg::BatteryViewMsg(msg) => {
                self.battery.update(msg);
            }
            AppletsMsg::ButtonClicked => {
                println!("Hello World");
            }
            AppletsMsg::MonitorMsg(msg) => {
                self.monitor.update(msg);
            }
            AppletsMsg::BatteryTimer => {
                self.battery.update(BatteryViewMsg::BatteryRefresh);
            }
            AppletsMsg::AudioMsg(msg) => {
                self.audio.update(msg);
            }
            AppletsMsg::SwitchView(kind) => {
                self.kind = kind;
            }
        }
        Command::none()
    }
    fn view(&mut self) -> Element<AppletsMsg, Renderer> {
        match self.kind {
            ControlType::Monitor => self.monitor.view().map(|msg| AppletsMsg::MonitorMsg(msg)),
            ControlType::Sound => self.audio.view().map(|msg| AppletsMsg::AudioMsg(msg)),
            ControlType::Wifi => Text::new("Wifi").into(),
            ControlType::Battery => self
                .battery
                .view()
                .map(|msg| AppletsMsg::BatteryViewMsg(msg)),
            ControlType::Default => Container::new(Text::new("Default"))
                .width(Length::Fill)
                .height(Length::Fill)
                .into(),
        }
    }
}
