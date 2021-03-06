use super::common::*;
use super::panel::Message as PanelMessage;
use crate::styles::{containers::CustomContainer, progress_bar::ProgressType, slider::SliderType};
use battery::{units::ratio::percent, Batteries, Battery as BatteryInfo, Manager};
use iced_wgpu::Renderer;
use iced_winit::{
    slider, Align, Application, Column, Command, Container, Element, HorizontalAlignment, Length,
    Program, ProgressBar, Row, Slider, Space, Text,
};
use libkoompi::system_settings::devices::Brightness;
use std::any::type_name;

#[derive(Debug)]
pub struct Battery {
    // data state
    pub current_battery: f32,
    battery_health: f32,
    is_full: bool,
    is_charging: bool,
    is_discharged: bool,
    manager: Manager,
    battery_info: BatteryInfo,
}
#[derive(Debug, Default)]
struct Display {
    current_bright: String,
}
#[derive(Debug)]
pub struct BatteryView {
    pub battery_state: Battery,
    display_state: Display,
    // ui state
    display_slide: slider::State,
    brigth_level: u32,
    battery_level: f32,
    brightness: Brightness,
}

#[derive(Debug, Clone)]
pub enum BatteryViewMsg {
    OnBrightChanged(u32),
    BatteryRefresh,
}

impl Program for BatteryView {
    type Message = BatteryViewMsg;
    type Renderer = self::Renderer;
    fn update(&mut self, msg: self::BatteryViewMsg) -> Command<BatteryViewMsg> {
        match msg {
            BatteryViewMsg::OnBrightChanged(val) => {
                self.brigth_level = val;
                self.display_state.current_bright = val.to_string();
                match self.brightness.login1_set_brightness(val) {
                    Ok(()) => {}
                    Err(e) => println!("Error: {:?}", e),
                }
            }
            BatteryViewMsg::BatteryRefresh => {
                match self
                    .battery_state
                    .manager
                    .refresh(&mut self.battery_state.battery_info)
                {
                    Ok(()) => {}
                    Err(e) => eprintln!("Error: {:?}", e),
                }
                self.battery_state.current_battery =
                    (self.battery_state.battery_info.state_of_charge().value * 100.0).ceil();
            }
        };
        Command::none()
    }
    fn view(&mut self) -> Element<BatteryViewMsg, Renderer> {
        let time = match self.battery_state.battery_info.time_to_empty() {
            Some(remaining_time) => remaining_time.value,
            None => match self.battery_state.battery_info.time_to_full() {
                Some(time) => time.value,
                None => 0.10,
            },
        };
        let brigtness = Row::new()
            .align_items(Align::Center)
            .spacing(10)
            .push(
                icon('\u{f108}')
                    .size(24)
                    .width(Length::Units(20))
                    .horizontal_alignment(HorizontalAlignment::Center),
            )
            .push(
                Column::new()
                    .align_items(Align::Center)
                    .push(
                        Row::new()
                            .spacing(4)
                            .align_items(Align::Center)
                            .push(Text::new("Display Brightness"))
                            .push(Space::with_width(Length::Fill))
                            .push(Text::new(format!(
                                "{}%",
                                self.display_state.current_bright.as_str()
                            ))),
                    )
                    .push(
                        Slider::new(
                            &mut self.display_slide,
                            0..=100,
                            self.brigth_level,
                            BatteryViewMsg::OnBrightChanged,
                        )
                        .style(SliderType::Default),
                    ),
            );
        let battery = Row::new()
            .align_items(Align::Center)
            .spacing(10)
            .push(
                condition(self.battery_state.current_battery)
                    .size(24)
                    .width(Length::Units(20)),
            )
            .push(
                Column::new()
                    .spacing(4)
                    .align_items(Align::Center)
                    .push(
                        Row::new()
                            .spacing(4)
                            .align_items(Align::Center)
                            .push(Text::new("Battery"))
                            .push(Space::with_width(Length::Fill))
                            .push(Text::new(format!(
                                "{}%",
                                self.battery_state.current_battery.to_string()
                            ))),
                    )
                    .push(
                        ProgressBar::new(0.0..=100.0, self.battery_level)
                            .width(Length::Fill)
                            .height(Length::Units(6))
                            .style(ProgressType::Default),
                    )
                    .push(
                        Row::new()
                            .push(Text::new("Remaining Time: "))
                            .push(Space::with_width(Length::Fill))
                            .push(Text::new(format!("{}", time.to_string()))),
                    )
                    .push(
                        Row::new()
                            .spacing(10)
                            .push(Text::new("Battery Health: "))
                            .push(Space::with_width(Length::Fill))
                            .push(Text::new(format!(
                                "{}%",
                                (self.battery_state.battery_info.state_of_health().value * 100.0)
                                    .floor()
                                    .to_string()
                            ))),
                    ),
            );
        Container::new(
            Column::new()
                .push(
                    Text::new("Battery and Brightness")
                        .size(18)
                        .horizontal_alignment(HorizontalAlignment::Left),
                )
                .align_items(Align::Center)
                .spacing(10)
                .push(brigtness)
                .push(battery),
        )
        .style(CustomContainer::ForegroundGray)
        .padding(10)
        .center_x()
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
    }
}
// fn convert_sec_to_string(value: f32) -> String {
//     if value / 60 ==
// }
// self.battery_state
//                                     .battery_info
//                                     .time_to_empty()
//                                     .unwrap()
//                                     .value
impl Application for BatteryView {
    type Flags = ();
    fn new(_flags: Self::Flags) -> (Self, Command<BatteryViewMsg>) {
        let (btr, manager) = get_battery().unwrap();
        let battery = Battery {
            current_battery: btr.state_of_charge().value * 100.0,
            battery_info: btr,
            battery_health: 0.0,
            is_full: false,
            is_charging: false,
            is_discharged: false,
            manager,
        };
        let init_battery_level = battery.current_battery;
        let brigth = Brightness::new();
        let display_state = Display {
            current_bright: brigth.get_percent().to_string(),
        };
        let level = brigth.get_percent();
        (
            Self {
                battery_state: battery,
                brigth_level: level,
                battery_level: init_battery_level,
                display_slide: slider::State::new(),
                display_state,
                brightness: brigth,
            },
            Command::none(),
        )
    }
    fn title(&self) -> String {
        String::from("Nothing")
    }
}
use std::io::{Error, ErrorKind};

fn get_battery() -> battery::Result<(BatteryInfo, Manager)> {
    let manager = battery::Manager::new()?;
    let battery = match manager.batteries()?.next() {
        Some(Ok(battery)) => battery,
        Some(Err(e)) => {
            eprintln!("Unable to access battery information");
            return Err(e);
        }
        None => {
            eprintln!("Unable to find any batteries");
            return Err(Error::from(ErrorKind::NotFound).into());
        }
    };

    Ok((battery, manager))
}

fn print_type_of<T>(_: &T) {
    println!("{}", type_name::<T>())
}
