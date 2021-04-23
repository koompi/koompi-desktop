use super::applets::ControlType;
use super::common::*;
use crate::styles::buttonstyle::buttons::ButtonStyle;
use chrono::Timelike;

use iced_wgpu::Renderer;
use iced_winit::{
    application::Application, button, winit, Align, Button, Color, Command, Container, Element,
    Image, Length, Program, Row, Space, Subscription, Svg, Text,
};
// use std::{cell::RefCell, rc::Rc};
use winit::event_loop::EventLoopProxy;
#[derive(Debug)]
pub struct DesktopPanel {
    pub background_color: Color,
    pub widgets: [button::State; 5],
    pub is_exit: bool,
    pub is_shown: bool,
    pub pre_kind: ControlType,
    pub kind: ControlType,
    pub now: chrono::DateTime<chrono::Local>,
    task_list: Vec<(button::State, TaskManager)>,
    task_count: usize,
    test_button: button::State,
    proxy: EventLoopProxy<Message>,
    monitor_visible: bool,
    sound_visible: bool,
    battery_visible: bool,
    wifi_visible: bool,
    battery_level: f32,
}
#[derive(Debug)]
struct TaskManager {
    pub id: u32,
    pub name: String,
    pub icon: String,
    pub sub_task: Vec<u32>,
    pub size: usize,
    pub count: usize,
}
impl Default for TaskManager {
    fn default() -> Self {
        Self {
            id: 0,
            name: "Rust".to_string(),
            icon: "rust".to_string(),
            sub_task: vec![],
            size: 20,
            count: 0,
        }
    }
}

impl Application for DesktopPanel {
    type Flags = EventLoopProxy<Message>;
    fn new(flags: Self::Flags) -> (Self, Command<Message>) {
        (
            Self {
                background_color: Color::from_rgb8(255, 255, 255),
                widgets: Default::default(),
                is_exit: false,
                is_shown: false,
                pre_kind: ControlType::Monitor,
                kind: ControlType::Monitor,
                task_list: vec![],
                task_count: 0,
                test_button: button::State::new(),
                now: chrono::Local::now(),
                proxy: flags,
                monitor_visible: false,
                sound_visible: false,
                battery_visible: false,
                wifi_visible: false,
                battery_level: 0.0,
            },
            Command::none(),
        )
    }
    fn title(&self) -> String {
        String::from("Title ")
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
    BatteryUpdate(f32),
    ShowPwdDialog(String),
    ActiveWindow(u32),
    RequestExit,
    OnMaxMinChange,
    OnTaskActive,
    Timer,
}

impl Program for DesktopPanel {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::BackgroundColorChanged(color) => {
                self.background_color = color;
            }
            Message::ShowAction => {}
            Message::ShowMenu => {
                self.proxy.send_event(Message::ShowMenu).ok();
            }
            Message::RequestExit => {
                self.proxy.send_event(Message::RequestExit).ok();
            }
            Message::ShowPwdDialog(pwd) => {
                println!("Data: {:?}", pwd);
            }
            Message::ActiveWindow(win_id) => {
                self.task_list.retain(|(_, v)| v.id != win_id);
                self.task_list.push((
                    button::State::new(),
                    TaskManager {
                        id: win_id,
                        ..Default::default()
                    },
                ));
                self.task_count += 1;
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
            Message::OnTaskActive => {}

            Message::BatteryUpdate(battery) => {
                self.battery_level = battery;
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
            Message::OnMaxMinChange => {}
            Message::Timer => {
                self.now = chrono::Local::now();
            }
            Message::Tick(local_time) => {
                println!("Tick ");
                let now = local_time;

                if now != self.now {
                    self.now = now;
                }
            }
        }
        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let [b1, b2, b3, b6, b7] = &mut self.widgets;
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
        let task_manager = if self.task_count > 0 {
            self.task_list.iter_mut().fold(
                Row::new().spacing(4),
                |row: Row<Message, Renderer>, (btn, task)| {
                    row.push(
                        Button::new(btn, Text::new("firefox")).on_press(Message::OnMaxMinChange),
                    )
                },
            )
        } else {
            Row::new()
        };
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
                Button::new(b3, condition(self.battery_level))
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
                "{}:{}",
                current_time.hour().to_string(),
                current_time.minute().to_string()
            )));
        let row = Row::new()
            .width(Length::Fill)
            .height(Length::Fill)
            .align_items(Align::End)
            .push(menu)
            .push(task_manager)
            .push(Space::with_width(Length::Fill))
            .push(system_tray);
        Container::new(row)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}

fn monitor_icon() -> Text<Renderer> {
    icon('\u{f108}')
}

fn sound_icon() -> Text<Renderer> {
    icon('\u{f028}')
}
fn wifi_icon() -> Text<Renderer> {
    icon('\u{f1eb}')
}
