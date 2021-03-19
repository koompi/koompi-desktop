use super::applets::ControlType;
use super::common::icon;
use crate::styles::buttonstyle::buttons::ButtonStyle;
use chrono::Timelike;
use iced::time;
use iced::{svg::Svg, Text};
use iced_wgpu::Renderer;
use iced_winit::{
    application::{Application, State},
    button, subscription, svg, Align, Button, Color, Column, Command, Container, Element, Font,
    HorizontalAlignment, Length, Program, Row, Space, Subscription,
};
#[derive(Debug)]
pub struct Controls {
    pub background_color: Color,
    pub widgets: [button::State; 7],
    pub is_exit: bool,
    pub is_shown: bool,
    pub kind: ControlType,
    now: chrono::DateTime<chrono::Local>,
}

impl Application for Controls {
    type Flags = ();
    fn new(flags: ()) -> (Self, Command<Message>) {
        (
            Controls {
                background_color: Color::from_rgb8(255, 255, 255),
                widgets: Default::default(),
                is_exit: false,
                is_shown: false,
                kind: ControlType::Monitor,
                now: chrono::Local::now(),
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
    MonitorShow,
    BellShow,
    KeyboardShow,
    ClipboardShow,
    SoundShow,
    WifiShow,
    Tick(chrono::DateTime<chrono::Local>),
}
impl Controls {
    pub fn is_quit(&mut self) -> bool {
        self.is_exit
    }
    pub fn is_shown(&self) -> bool {
        self.is_shown
    }
    pub fn background_color(&self) -> Color {
        self.background_color
    }
    pub fn get_kind(&self) -> ControlType {
        self.kind
    }
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
                self.is_exit = !self.is_exit;
            }
            Message::MonitorShow => {
                println!("Application show");
                self.is_shown = !self.is_shown;
                self.kind = ControlType::Monitor;
            }
            Message::BellShow => {
                self.kind = ControlType::Bell;
            }
            Message::ClipboardShow => {
                self.kind = ControlType::Clipboard;
            }
            Message::SoundShow => {
                self.kind = ControlType::Sound;
            }
            Message::WifiShow => {
                self.kind = ControlType::Wifi;
                self.now = chrono::Local::now();
            }
            Message::KeyboardShow => {
                self.kind = ControlType::Keyboard;
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
        let current_time = self.now.time();
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
                    .on_press(Message::MonitorShow)
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b7, wifi_icon())
                    .height(Length::Fill)
                    .on_press(Message::WifiShow)
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b3, bell_icon())
                    .height(Length::Fill)
                    .on_press(Message::BellShow)
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b4, keyboard_icon())
                    .on_press(Message::KeyboardShow)
                    .height(Length::Fill)
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b5, clipboard())
                    .height(Length::Fill)
                    .on_press(Message::ClipboardShow)
                    .style(ButtonStyle::Transparent),
            )
            .push(
                Button::new(b6, sound_icon())
                    .height(Length::Fill)
                    .on_press(Message::SoundShow)
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

fn menu_icon() -> Text {
    icon('\u{f0c9}')
}
fn monitor_icon() -> Text {
    icon('\u{f108}')
}
fn bell_icon() -> Text {
    icon('\u{f0f3}')
}
fn clipboard() -> Text {
    icon('\u{f328}')
}
fn keyboard_icon() -> Text {
    icon('\u{f11c}')
}
fn sound_icon() -> Text {
    icon('\u{f028}')
}
fn wifi_icon() -> Text {
    icon('\u{f1eb}')
}
