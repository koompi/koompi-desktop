use iced_wgpu::Renderer;
use iced_winit::{
    Color, Command, Container, Element, Length, Program, Grid, Button, Text, Column, button, 
    Align, HorizontalAlignment, Row, Tooltip, tooltip,
};
use iced::{Svg, Image};
use super::desktop_manager::DesktopManager;
use super::errors::DesktopError;
use super::styles::{CustomButton, CustomTooltip};

const DESKTOP_CONF: &str = "desktop/desktop.toml";

pub struct Desktop {
    desktop_manager: DesktopManager,
    desktop_items_state: Vec<button::State>,
    selected_desktop_item: Option<usize>,
    background_color: Color,
}

#[derive(Debug, Clone)]
pub enum Message {
    DesktopItemClicked(usize),
}

impl Desktop {
    pub fn new() -> Result<Desktop, DesktopError> {
        let desktop_manager = DesktopManager::new(dirs_next::config_dir().unwrap().join(DESKTOP_CONF))?;

        Ok(Desktop {
            desktop_items_state: vec![button::State::new(); desktop_manager.desktop_items().len()],
            desktop_manager,
            background_color: Color::BLACK,
            selected_desktop_item: None
        })
    }

    pub fn background_color(&self) -> Color {
        self.background_color
    }
}

impl Program for Desktop {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::DesktopItemClicked(idx) => self.selected_desktop_item = Some(idx)
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let Self {
            desktop_items_state,
            desktop_manager,
            selected_desktop_item,
            ..
        } = self;

        let desktop_items = desktop_manager.desktop_items();
        let desktop_conf = desktop_manager.config();
        let icon_size = desktop_conf.desktop_item_conf().icon_size;
        let item_size = icon_size + 50;

        let desktop_grid = desktop_items_state.iter_mut().zip(desktop_items).enumerate()
            .fold(Grid::new().column_width(item_size).width(Length::Fill).height(Length::Fill).padding(20), |grid, (idx, (state, item))| {
                let name = item.name().unwrap_or(String::from("Unknown Name"));
                let icon_path = item.icon();
                let comment = item.comment();

                let icon: Element<Message, Renderer> = if let Some(extension) = icon_path.extension() {
                    if extension == "svg" {
                        Svg::from_path(icon_path).width(Length::Units(icon_size)).height(Length::Units(icon_size)).into()
                    } else {
                        Image::new(icon_path).width(Length::Units(icon_size)).height(Length::Units(icon_size)).into()
                    }
                } else {
                    Row::new().into()
                };
                let con = Column::new().width(Length::Fill).height(Length::Fill).align_items(Align::Center)
                    .push(icon)
                    .push(Text::new(name).size(13).horizontal_alignment(HorizontalAlignment::Center));

                let mut btn = Button::new(state, con)
                    .width(Length::Units(item_size))
                    .height(Length::Units(item_size))
                    .padding(10)
                    .on_press(Message::DesktopItemClicked(idx));
                if let Some(curr_idx) = *selected_desktop_item {
                    if curr_idx == idx {
                        btn = btn.style(CustomButton::Selected);
                    } else {
                        btn = btn.style(CustomButton::Transparent);
                    }
                } else {
                    btn = btn.style(CustomButton::Transparent);
                }

                // let tooltip_btn: Element<Message, Renderer> = if let Some(cmt) = comment {
                //     Tooltip::new(btn, cmt, tooltip::Position::Top).gap(5).padding(4).style(CustomTooltip).into()
                // } else {
                //     btn.into()
                // };

                grid.push(btn)
            });

        Container::new(desktop_grid)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}
