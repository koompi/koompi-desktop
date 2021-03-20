use iced_wgpu::Renderer;
use iced_winit::{
    Color, Command, Container, Element, Length, Program, Grid, Button, Text, Column, button, mouse::{self, click}, touch,
    Align, HorizontalAlignment, Row, Tooltip, tooltip, Space, Application, Event, Subscription, Point,
};
use iced::{Svg, Image};
use crate::configs::{
    DesktopConf,
    background_conf::BackgroundType,
    desktop_item_conf::Arrangement,
};
use crate::desktop_item::DesktopItem;
use super::styles::{CustomButton, CustomTooltip};

#[derive(Debug, Clone, Default)]
pub struct Desktop {
    desktop_conf: DesktopConf,
    ls_desktop_items: Vec<(button::State, DesktopItem)>,
    selected_desktop_item: Option<usize>,
    height: u32,
    last_click: Option<mouse::Click>,
    cursor_position: Point,
}

#[derive(Debug, Clone)]
pub enum Message {
    DesktopItemClicked(usize),
    WinitEvent(Event)
}

impl Application for Desktop {
    type Flags = (u32, DesktopConf, Vec<DesktopItem>);

    fn new(flags: Self::Flags) -> (Self, Command<Message>) { 
        (
            Self {
                desktop_conf: flags.1.to_owned(),
                ls_desktop_items: flags.2.iter().map(|item| (button::State::new(), item.to_owned())).collect(),
                height: flags.0,
                ..Self::default()
            },
            Command::none()
        )
    }

    fn title(&self) -> String { 
        String::from("Desktop")
    }

    fn subscription(&self) -> Subscription<Message> {
        iced_winit::subscription::events().map(Message::WinitEvent)
    }

    fn background_color(&self) -> Color {
        let bg_conf = self.desktop_conf.background_conf();
        match bg_conf.kind {
            BackgroundType::Color => hex_to_color(&bg_conf.color_background).unwrap(),
            BackgroundType::Wallpaper => Color::TRANSPARENT
        }
    }
}

impl Program for Desktop {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::DesktopItemClicked(idx) => self.selected_desktop_item = Some(idx),
            Message::WinitEvent(event) => match event {
                Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left))
                | Event::Touch(touch::Event::FingerPressed { .. }) => {
                    let click = mouse::Click::new(
                        self.cursor_position,
                        self.last_click,
                    );

                    match click.kind() {
                        click::Kind::Double => {
                            println!("handled double clicked");
                            if let Some(idx) = self.selected_desktop_item {
                                if let Some((_, desktop_item)) = self.ls_desktop_items.get_mut(idx) {
                                    desktop_item.handle_exec();
                                }
                            }
                        }
                        _ => {}
                    }

                    self.last_click = Some(click);
                },
                Event::Mouse(mouse::Event::CursorMoved { position })
                | Event::Touch(touch::Event::FingerMoved { position, .. }) => {
                    self.cursor_position = position;
                },
                _ => {}
            }
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let Self {
            desktop_conf,
            ls_desktop_items,
            selected_desktop_item,
            ..
        } = self;

        let item_conf = desktop_conf.desktop_item_conf();
        let grid_spacing = item_conf.grid_spacing;
        let item_size = item_conf.icon_size + 35;
        let item_size_spacing = item_size + grid_spacing;
        let mut grid = Grid::new().column_width(item_size_spacing).padding(20).spacing(grid_spacing);
        if let Arrangement::Columns = item_conf.arrangement {
            let items_in_height = item_size_spacing as usize*ls_desktop_items.len() + 40;
            grid = grid.columns((items_in_height as f32/self.height as f32).ceil() as usize);
        }

        let desktop_grid = ls_desktop_items.iter_mut().enumerate()
            .fold(grid, |grid, (idx, (state, item))| {
                let icon: Element<Message, Renderer> = if let Some(icon_path) = &item.icon_path {
                    if let Some(extension) = icon_path.extension() {
                        if extension == "svg" {
                            Svg::from_path(icon_path).width(Length::Units(item_conf.icon_size)).height(Length::Units(item_conf.icon_size)).into()
                        } else {
                            Image::new(icon_path).width(Length::Units(item_conf.icon_size)).height(Length::Units(item_conf.icon_size)).into()
                        }
                    } else {
                        Row::new().into()
                    }
                } else {
                    Row::new().into()
                };
                let con = Column::new().spacing(10).align_items(Align::Center)
                    .push(icon)
                    .push(Text::new(item.name.as_ref().unwrap_or(&"Unknown name".to_string())).horizontal_alignment(HorizontalAlignment::Center));

                let mut btn = Button::new(state, con)
                    .width(Length::Units(item_size))
                    .padding(7)
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

                let tooltip_btn: Element<Message, Renderer> = if item_conf.show_tooltip {
                    if let Some(cmt) = &item.comment {
                        Tooltip::new(btn, cmt, tooltip::Position::FollowCursor).size(12).gap(5).padding(5).style(CustomTooltip).into()
                    } else {
                        btn.into()
                    }
                } else {
                    btn.into()
                };

                grid.push(
                    Container::new(tooltip_btn).center_x().center_y()
                )
            });

        Container::new(
            Column::new()
            .push(Space::with_height(Length::Units(30)))
            .push(desktop_grid)
        )
        .width(Length::Fill)
        .height(Length::Fill).into()
    }
}


fn hex_to_color(hex: &str) -> Option<Color> {
    if hex.len() == 7 {
        let hash = &hex[0..1];
        let r = u8::from_str_radix(&hex[1..3], 16);
        let g = u8::from_str_radix(&hex[3..5], 16);
        let b = u8::from_str_radix(&hex[5..7], 16);

        return match (hash, r, g, b) {
            ("#", Ok(r), Ok(g), Ok(b)) => Some(Color {
                r: r as f32 / 255.0,
                g: g as f32 / 255.0,
                b: b as f32 / 255.0,
                a: 1.0,
            }),
            _ => None,
        };
    }

    None
}