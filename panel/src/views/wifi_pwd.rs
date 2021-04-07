use super::common::icon;
use super::panel::Message;
use crate::styles::buttonstyle::buttons::ButtonStyle;
use iced_wgpu::Renderer;
use iced_winit::{
    button, text_input, winit::event_loop::EventLoopProxy, Align, Application, Button, Column,
    Command, Container, Element, HorizontalAlignment, Length, Program, Row, Space, Text, TextInput,
};
#[derive(Debug)]
pub struct WifiPwdView {
    ssid: String,
    pwd_input: text_input::State,
    password: String,
    connect_btn: button::State,
    cancel_btn: button::State,
    toggler_bnt: button::State,
    is_connectable: bool,
    is_show: bool,
    proxy: EventLoopProxy<Message>,
}
impl WifiPwdView {
    pub fn new(proxy: EventLoopProxy<Message>) -> Self {
        Self {
            ssid: String::new(),
            pwd_input: text_input::State::new(),
            password: String::new(),
            connect_btn: button::State::new(),
            cancel_btn: button::State::new(),
            toggler_bnt: button::State::new(),
            is_connectable: false,
            is_show: false,
            proxy: proxy,
        }
    }
}
#[derive(Debug, Clone)]
pub enum WifiPwdViewMsg {
    OnToggler,
    OnConnect,
    OnCancel,
    OnPassword(String),
    AcceptSsid(String),
}

impl Program for WifiPwdView {
    type Renderer = Renderer;
    type Message = WifiPwdViewMsg;

    fn update(&mut self, msg: WifiPwdViewMsg) -> Command<WifiPwdViewMsg> {
        match msg {
            WifiPwdViewMsg::OnPassword(pwd) => {
                self.pwd_input.focus();
                if pwd.len() > 8 {
                    self.is_connectable = true;
                } else {
                    self.is_connectable = false;
                }
                self.password = pwd;
            }
            WifiPwdViewMsg::OnConnect => {}
            WifiPwdViewMsg::OnToggler => {
                self.is_show = !self.is_show;
            }
            WifiPwdViewMsg::OnCancel => {
                self.proxy.send_event(Message::RequestExit).ok();
            }
            WifiPwdViewMsg::AcceptSsid(ssid) => {
                self.ssid = ssid;
            }
        }
        Command::none()
    }
    fn view(&mut self) -> Element<WifiPwdViewMsg, Renderer> {
        let parent_layout = Column::new()
            .push(icon('\u{f1eb}').size(18))
            .align_items(Align::Center)
            .spacing(10)
            .push(Text::new(format!(
                "Passowrd required to connect to {} ",
                self.ssid
            )))
            .push(
                Row::new()
                    .spacing(4)
                    .align_items(Align::Center)
                    .push(Text::new("Passowrd: "))
                    .push(if self.is_show {
                        TextInput::new(
                            &mut self.pwd_input,
                            "PASSWORD",
                            &self.password,
                            WifiPwdViewMsg::OnPassword,
                        )
                        .padding(8)
                    } else {
                        TextInput::new(
                            &mut self.pwd_input,
                            "PASSWORD",
                            &self.password,
                            WifiPwdViewMsg::OnPassword,
                        )
                        .password()
                        .padding(8)
                    })
                    .push(
                        Button::new(
                            &mut self.toggler_bnt,
                            if self.is_show {
                                icon('\u{f0e6}')
                            } else {
                                icon('\u{f06e}')
                            },
                        )
                        .on_press(WifiPwdViewMsg::OnToggler)
                        .style(ButtonStyle::Transparent),
                    ),
            )
            .push(
                Row::new()
                    .align_items(Align::Center)
                    .spacing(4)
                    .push(
                        Button::new(
                            &mut self.cancel_btn,
                            Text::new("Cancel").horizontal_alignment(HorizontalAlignment::Center),
                        )
                        .on_press(WifiPwdViewMsg::OnCancel)
                        .style(ButtonStyle::Transparent)
                        .width(Length::Fill)
                        .padding(10),
                    )
                    .push(if self.is_connectable {
                        Button::new(
                            &mut self.connect_btn,
                            Text::new("Connect").horizontal_alignment(HorizontalAlignment::Center),
                        )
                        .on_press(WifiPwdViewMsg::OnConnect)
                        .width(Length::Fill)
                        .style(ButtonStyle::Transparent)
                        .padding(10)
                    } else {
                        Button::new(
                            &mut self.connect_btn,
                            Text::new("Connect").horizontal_alignment(HorizontalAlignment::Center),
                        )
                        .width(Length::Fill)
                        .style(ButtonStyle::Transparent)
                        .padding(10)
                    }),
            );
        Container::new(parent_layout)
            .padding(10)
            .height(Length::Fill)
            .width(Length::Fill)
            .center_y()
            .center_x()
            .into()
    }
}
