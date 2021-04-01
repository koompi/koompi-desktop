use super::battery::{BatteryView, BatteryViewMsg};
use super::common::icon;
use super::monitor::{Monitor, MonitorMsg};
use super::panel::Message;
use super::sound::{Audio, AudioMsg};
use super::wireless::{Wireless, WirelessMsg};
use crate::styles::containers::CustomContainer;
use iced_wgpu::Renderer;
use iced_winit::{
    button, slider, winit::event_loop::EventLoopProxy, Application, Command, Container, Element,
    Length, Program, Text,
};

#[derive(Debug)]
pub struct Applets {
    pub slider: slider::State,
    pub value: f32,
    pub mute: button::State,
    pub kind: ControlType,
    monitor: Monitor,
    audio: Audio,
    wireless: Wireless,
    pub battery: BatteryView,
    proxy: EventLoopProxy<Message>,
}
#[derive(Debug, Clone)]
pub enum AppletsMsg {
    SoundChanged(f32),
    ButtonClicked,
    MonitorMsg(MonitorMsg),
    WirelessMsg(WirelessMsg),
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
impl Application for Applets {
    type Flags = EventLoopProxy<Message>;
    fn new(flags: Self::Flags) -> (Self, Command<AppletsMsg>) {
        (
            Self {
                battery: BatteryView::new(()).0,
                audio: Audio::new(),
                monitor: Monitor::new(),
                kind: ControlType::Monitor,
                wireless: Wireless::new(),
                mute: button::State::new(),
                value: 0.0,
                slider: slider::State::new(),
                proxy: flags,
            },
            Command::none(),
        )
    }
    fn title(&self) -> String {
        String::from("Hello World")
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
            AppletsMsg::WirelessMsg(msg) => {
                self.wireless.update(msg);
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
            ControlType::Wifi => self.wireless.view().map(|msg| AppletsMsg::WirelessMsg(msg)),
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
