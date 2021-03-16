use super::sound::ControlType;
use super::state::CommonState;
use iced_wgpu::Renderer;
use iced_winit::{
    button, Align, Button, Color, Column, Command, Container, Element, Font, HorizontalAlignment,
    Length, Program, Row, Slider, Space, Text,
};
#[derive(Debug, Default)]
pub struct Controls {
    pub background_color: Color,
    pub widgets: [button::State; 7],
    pub is_exit: bool,
    pub is_shwon: bool,
    pub kind: ControlType,
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
}
impl CommonState for Controls {
    fn get_name(&self) -> String {
        String::from("Panel Control")
    }
}
impl Controls {
    pub fn new() -> Controls {
        Controls {
            background_color: Color::from_rgb8(255, 255, 255),
            widgets: Default::default(),
            is_exit: false,
            is_shwon: false,
            ..Default::default()
        }
    }
    pub fn is_quit(&mut self) -> bool {
        self.is_exit
    }
    pub fn is_shown(&self) -> bool {
        self.is_shwon
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
                self.is_shwon = !self.is_shwon;
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
            }
            Message::KeyboardShow => {
                self.kind = ControlType::Keyboard;
            }
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let background_color = self.background_color;

        let [b1, b2, b3, b4, b5, b6, b7] = &mut self.widgets;
        let background_color = self.background_color;
        let menu = Button::new(b1, menu_icon())
            .on_press(Message::ShowMenu)
            .width(Length::Shrink)
            .height(Length::Shrink);
        let system_tray = Row::new()
            .align_items(Align::Center)
            .push(
                Button::new(b2, monitor_icon())
                    .height(Length::Fill)
                    .on_press(Message::MonitorShow),
            )
            .push(
                Button::new(b3, bell_icon())
                    .height(Length::Fill)
                    .on_press(Message::BellShow),
            )
            .push(Button::new(b4, keyboard_icon()).on_press(Message::KeyboardShow))
            .push(
                Button::new(b5, clipboard())
                    .height(Length::Fill)
                    .on_press(Message::ClipboardShow),
            )
            .push(
                Button::new(b6, sound_icon())
                    .height(Length::Fill)
                    .on_press(Message::SoundShow),
            )
            .push(
                Button::new(b7, wifi_icon())
                    .height(Length::Fill)
                    .on_press(Message::WifiShow),
            );
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

fn menu_icon() -> Text<Renderer> {
    icon('\u{f0c9}')
}
fn monitor_icon() -> Text<Renderer> {
    icon('\u{f108}')
}
fn bell_icon() -> Text<Renderer> {
    icon('\u{f0f3}')
}
fn clipboard() -> Text<Renderer> {
    icon('\u{f328}')
}
fn keyboard_icon() -> Text<Renderer> {
    icon('\u{f11c}')
}
fn sound_icon() -> Text<Renderer> {
    icon('\u{f028}')
}
fn wifi_icon() -> Text<Renderer> {
    icon('\u{f1eb}')
}
pub fn icon(unicode: char) -> Text<Renderer> {
    Text::new(&unicode.to_string())
        .font(ICONS)
        .width(Length::Units(20))
        .horizontal_alignment(HorizontalAlignment::Center)
        .size(20)
}
const ICONS: Font = Font::External {
    name: "Line Awesome",
    bytes: include_bytes!("./font/la-solid-900.ttf"),
};
