use super::applets::ControlType;
use super::common::icon;
use crate::styles::buttonstyle::buttons::ButtonStyle;
use chrono::Timelike;
use iced::time;
use iced::{svg::Svg, Text};
use iced_wgpu::Renderer;
use iced_winit::{
    application::Application, button, winit, Align, Button, Color, Command, Container, Element,
    Length, Program, Row, Space, Subscription,
};
use winit::event_loop::EventLoopProxy;
#[derive(Debug)]
pub struct Controls {
    pub background_color: Color,
    pub widgets: [button::State; 7],
    pub is_exit: bool,
    pub is_shown: bool,
    pub pre_kind: ControlType,
    pub kind: ControlType,
    pub now: chrono::DateTime<chrono::Local>,
    proxy: EventLoopProxy<Message>,
    monitor_visible: bool,
    sound_visible: bool,
    battery_visible: bool,
    wifi_visible: bool,
}

impl Application for Controls {
    type Flags = EventLoopProxy<Message>;
    fn new(flags: Self::Flags) -> (Self, Command<Message>) {
        (
            Controls {
                background_color: Color::from_rgb8(255, 255, 255),
                widgets: Default::default(),
                is_exit: false,
                is_shown: false,
                pre_kind: ControlType::Monitor,
                kind: ControlType::Monitor,
                now: chrono::Local::now(),
                proxy: flags,
                monitor_visible: false,
                sound_visible: false,
                battery_visible: false,
                wifi_visible: false,
            },
            Command::none(),
        )
    }
    fn title(&self) -> String {
        String::from("Title ")
    }
    fn subscription(&self) -> Subscription<Message> {
        time::every(std::time::Duration::from_millis(500))
            .map(|_| Message::Tick(chrono::Local::now()))
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    BackgroundColorChanged(Color),
    ShowAction,
    ShowMenu,
    MonitorShow(bool),
    Battery(bool),
    SoundShow(bool),
    WifiShow(bool),
    Tick(chrono::DateTime<chrono::Local>),
    Timer,
}

impl Program for Controls {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::BackgroundColorChanged(color) => {
                self.background_color = color;
            }
            Message::ShowAction => {}
            Message::ShowMenu => {
                println!("Menu show");
                self.proxy.send_event(Message::ShowMenu).ok();
            }
            Message::WifiShow(_) => {
                self.wifi_visible = !self.wifi_visible;
                self.battery_visible = false;
                self.monitor_visible = false;
                self.sound_visible = false;
                self.proxy
                    .send_event(Message::WifiShow(self.wifi_visible))
                    .ok();
            }
            Message::Battery(_) => {
                self.battery_visible = !self.battery_visible;
                self.wifi_visible = false;
                self.sound_visible = false;
                self.monitor_visible = false;
                self.proxy
                    .send_event(Message::Battery(self.battery_visible))
                    .ok();
            }
            Message::MonitorShow(_) => {
                self.monitor_visible = !self.monitor_visible;
                self.sound_visible = false;
                self.battery_visible = false;
                self.wifi_visible = false;
                self.proxy
                    .send_event(Message::MonitorShow(self.monitor_visible))
                    .ok();
            }
            Message::SoundShow(_) => {
                self.sound_visible = !self.sound_visible;
                self.monitor_visible = false;
                self.battery_visible = false;
                self.wifi_visible = false;
                self.proxy
                    .send_event(Message::SoundShow(self.sound_visible))
                    .ok();
            }
            Message::Timer => {
                self.now = chrono::Local::now();
                println!("timer out running...");
            }
            Message::Tick(local_time) => {
                let now = local_time;

                if now != self.now {
                    self.now = now;
                }
            }
        }
        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let [b1, b2, b3, b4, b5, b6, b7] = &mut self.widgets;
        let current_time = self.now;
        let svg = Svg::from_path(format!(
            "{}/src/assets/images/koompi-black.svg",
            env!("CARGO_MANIFEST_DIR")
        ))
        .width(Length::Units(36))
        .height(Length::Units(36));
        let menu = Button::new(b1, svg)
            .on_press(Message::ShowMenu)
            .width(Length::Shrink)
            .height(Length::Shrink)
            .style(ButtonStyle::Transparent);
        let system_tray = Row::new()
            .align_items(Align::Center)
            .push(
                Button::new(b2, monitor_icon())
                    .height(Length::Fill)
                    .on_press(Message::MonitorShow(true))
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b7, wifi_icon())
                    .height(Length::Fill)
                    .on_press(Message::WifiShow(true))
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b3, battery_icon())
                    .height(Length::Fill)
                    .on_press(Message::Battery(true))
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b6, sound_icon())
                    .height(Length::Fill)
                    .on_press(Message::SoundShow(true))
                    .style(ButtonStyle::Transparent),
            )
            .push(Text::new(format!(
                "{}:{}:{}",
                current_time.hour().to_string(),
                current_time.minute().to_string(),
                current_time.second().to_string()
            )));
        let row = Row::new()
            .width(Length::Fill)
            .height(Length::Fill)
            .align_items(Align::End)
            .push(menu)
            .push(Space::with_width(Length::Fill))
            .push(system_tray);
        Container::new(row)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}

// fn menu_icon() -> Text {
//     icon('\u{f0c9}')
// }
fn monitor_icon() -> Text {
    icon('\u{f108}')
}
fn battery_icon() -> Text {
    icon('\u{f240}')
}
// fn clipboard() -> Text {
//     icon('\u{f328}')
// }
// fn keyboard_icon() -> Text {
//     icon('\u{f11c}')
// }
fn sound_icon() -> Text {
    icon('\u{f028}')
}
fn wifi_icon() -> Text {
    icon('\u{f1eb}')
}
