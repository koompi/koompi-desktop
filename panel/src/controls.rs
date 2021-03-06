use crate::styles::buttonstyle::buttons::ButtonStyle::Transparent as btnzero;
use crate::styles::containers::CustomContainer::ForegroundWhite;

use iced_wgpu::Renderer;
use iced_winit::{
    button, Align, Button, Color, Column, Command, Container, Element, Font, HorizontalAlignment,
    Length, Program, Row, Slider, Space, Text,
};
#[derive(Debug, Default, Copy, Clone)]
pub struct Controls {
    background_color: Color,
    widgets: [button::State; 7],
    is_exit: bool,
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

impl Controls {
    pub fn new() -> Controls {
        Controls {
            background_color: Color::BLACK,
            widgets: Default::default(),
            is_exit: false,
        }
    }
    pub fn is_quit(&self) -> bool {
        self.is_exit
    }

    pub fn background_color(&self) -> Color {
        self.background_color
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
            Message::ShowAction => {
                println!("Application show");
            }
            Message::ShowMenu => {
                println!("Menu show");
                self.is_exit = !self.is_exit;
            }
            Message::MonitorShow => {}
            Message::BellShow => {}
            Message::ClipboardShow => {}
            Message::SoundShow => {}
            Message::WifiShow => {}
            Message::KeyboardShow => {}
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let background_color = self.background_color;

        let [b1, b2, b3, b4, b5, b6, b7] = &mut self.widgets;
        let background_color = self.background_color;
        let menu = Button::new(b1, menu_icon())
            .style(btnzero)
            .on_press(Message::ShowMenu)
            .width(Length::Shrink)
            .height(Length::Shrink);
        let system_tray = Row::new()
            .align_items(Align::Center)
            .push(
                Button::new(b2, monitor_icon())
                    .height(Length::Fill)
                    .style(btnzero)
                    .on_press(Message::MonitorShow),
            )
            .push(
                Button::new(b3, bell_icon())
                    .style(btnzero)
                    .height(Length::Fill)
                    .on_press(Message::BellShow),
            )
            .push(
                Button::new(b4, keyboard_icon())
                    .style(btnzero)
                    .on_press(Message::KeyboardShow),
            )
            .push(
                Button::new(b5, clipboard())
                    .style(btnzero)
                    .height(Length::Fill)
                    .on_press(Message::ClipboardShow),
            )
            .push(
                Button::new(b6, sound_icon())
                    .style(btnzero)
                    .height(Length::Fill)
                    .on_press(Message::SoundShow),
            )
            .push(
                Button::new(b7, wifi_icon())
                    .style(btnzero)
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
            .style(ForegroundWhite)
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
fn icon(unicode: char) -> Text<Renderer> {
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

pub struct Widgets {}
