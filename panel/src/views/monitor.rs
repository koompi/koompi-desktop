use crate::styles::containers::CustomContainer;
use iced::svg::Svg;
use iced_wgpu::Renderer;
use iced_winit::{
    button, checkbox, program, Align, Button, Checkbox, Column, Command, Container, Element,
    Length, Program, Row, Text,
};
#[derive(Debug, Default)]
pub struct Monitor {
    is_present_mode: bool,
    monitor: [button::State; 5],
    test: button::State,
}
#[derive(Debug, Clone)]
pub enum MonitorMsg {
    OnPresent(bool),
    OnScreenMode,
    External,
    Laptop,
    Unify,
    ExtendLeft,
    ExtendRight,
}

impl Monitor {
    pub fn new() -> Self {
        Self { ..Self::default() }
    }
}
impl Program for Monitor {
    type Renderer = self::Renderer;
    type Message = self::MonitorMsg;

    fn update(&mut self, msg: self::MonitorMsg) -> Command<MonitorMsg> {
        match msg {
            MonitorMsg::OnPresent(is_present) => {
                self.is_present_mode = is_present;
            }
            MonitorMsg::OnScreenMode => {
                println!("You click change display mode");
            }
            MonitorMsg::External => {}
            MonitorMsg::Laptop => {}
            MonitorMsg::ExtendLeft => {}
            MonitorMsg::ExtendRight => {}
            MonitorMsg::Unify => {}
        }
        Command::none()
    }
    fn view(&mut self) -> Element<self::MonitorMsg, self::Renderer> {
        let [b1, b2, b3, b4, b5] = &mut self.monitor;
        let svg = Svg::from_path(format!(
            "{}/src/assets/images/monitor.svg",
            env!("CARGO_MANIFEST_DIR")
        ))
        .width(Length::Units(36))
        .height(Length::Units(36));
        let [svg1, svg2, svg3, svg4] = [svg.clone(), svg.clone(), svg.clone(), svg.clone()];
        Container::new(
            Column::new()
                .spacing(10)
                .align_items(Align::Start)
                .push(Text::new("Screen Layout").size(18))
                .push(
                    Row::new()
                        .align_items(Align::Center)
                        .spacing(10)
                        .padding(10)
                        .push(
                            Button::new(b1, svg)
                                .padding(10)
                                .on_press(MonitorMsg::External),
                        )
                        .push(
                            Button::new(b2, svg1)
                                .padding(10)
                                .on_press(MonitorMsg::Laptop),
                        )
                        .push(
                            Button::new(b3, svg2)
                                .padding(10)
                                .on_press(MonitorMsg::Unify),
                        )
                        .push(
                            Button::new(b4, svg3)
                                .padding(10)
                                .on_press(MonitorMsg::ExtendLeft),
                        )
                        .push(
                            Button::new(b5, svg4)
                                .padding(10)
                                .on_press(MonitorMsg::ExtendRight),
                        ),
                )
                .push(Checkbox::new(
                    self.is_present_mode,
                    "Enable Presentation Mode",
                    MonitorMsg::OnPresent,
                ))
                .push(Text::new(
                    "This settings will prevent your computer from turning off automatically",
                )),
        )
        .width(Length::Fill)
        .height(Length::Fill)
        .style(CustomContainer::ForegroundGray)
        .padding(10)
        .center_x()
        .into()
    }
}
