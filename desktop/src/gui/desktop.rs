use iced_wgpu::Renderer;
use iced_winit::{
    Color, Command, Container, Element, Length, Program, Grid, Button, Text, Column, button, keyboard, Row, 
    Align, HorizontalAlignment, Tooltip, tooltip, Space, Application, Event, Subscription, Clipboard,
};
use iced::{Svg, Image};
use std::{cell::RefCell, rc::Rc};
use crate::configs::{
    DesktopConf,
    background_conf::BackgroundType,
    desktop_item_conf::Arrangement,
};
use crate::desktop_item::DesktopItem;
use super::styles::{CustomButton, CustomTooltip};

#[derive(Debug)]
pub struct Desktop {
    desktop_conf: Rc<RefCell<DesktopConf>>,
    ls_desktop_items: Vec<(button::State, DesktopItem)>,
    selected_desktop_item: Option<usize>,
    height: u32,
}

#[derive(Debug, Clone)]
pub enum DesktopMsg {
    DesktopItemClicked(usize),
    LaunchDesktopItem(usize),
    WinitEvent(Event)
}

impl Desktop {
    fn handle_exec(&mut self, idx: usize) {
        if let Some((_, desktop_item)) = self.ls_desktop_items.get_mut(idx) {
            match desktop_item.handle_exec() {
                Ok(()) => {},
                Err(err) => eprintln!("{}", err)
            }
        }
    }
}

impl Application for Desktop {
    type Flags = (u32, Rc<RefCell<DesktopConf>>, Vec<DesktopItem>);

    fn new(flags: Self::Flags) -> (Self, Command<DesktopMsg>) { 
        (
            Self {
                desktop_conf: flags.1,
                ls_desktop_items: flags.2.iter().map(|item| (button::State::new(), item.to_owned())).collect(),
                height: flags.0,
                selected_desktop_item: None,
            },
            Command::none()
        )
    }

    fn title(&self) -> String { 
        String::from("Desktop")
    }

    fn subscription(&self) -> Subscription<DesktopMsg> {
        iced_winit::subscription::events().map(DesktopMsg::WinitEvent)
    }

    fn background_color(&self) -> Color {
        let desktop_conf = self.desktop_conf.borrow();
        let bg_conf = &desktop_conf.background_conf;

        match bg_conf.kind {
            BackgroundType::Color => bg_conf.color_background,
            BackgroundType::Wallpaper => Color::TRANSPARENT
        }
    }
}

impl Program for Desktop {
    type Renderer = Renderer;
    type Message = DesktopMsg;
    type Clipboard = Clipboard;

    fn update(&mut self, message: Self::Message, _clipboard: &mut Clipboard) -> Command<Self::Message> {
        use DesktopMsg::*;

        match message {
            DesktopItemClicked(idx) => self.selected_desktop_item = Some(idx),
            LaunchDesktopItem(idx) => self.handle_exec(idx),
            WinitEvent(event) => {
                match event {
                    Event::Keyboard(key_event) => match key_event {
                        keyboard::Event::CharacterReceived('\r') => if let Some(idx) = self.selected_desktop_item {
                            self.handle_exec(idx);
                        },
                        keyboard::Event::KeyPressed { key_code, .. } => match key_code {
                            keyboard::KeyCode::Right => if let Some(idx) = &mut self.selected_desktop_item {
                                if *idx<self.ls_desktop_items.len()-1 {
                                    *idx+=1;
                                } else {
                                    *idx = 0;
                                }
                            } else {
                                self.selected_desktop_item = Some(0);
                            },
                            keyboard::KeyCode::Left => if let Some(idx) = &mut self.selected_desktop_item {
                                if *idx>0 {
                                    *idx-=1;
                                } else {
                                    *idx = self.ls_desktop_items.len()-1;
                                }
                            } else {
                                self.selected_desktop_item = Some(0);
                            },
                            _ => {}
                        },
                        _ => {}
                    } 
                    _ => {}
                }
            }
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Self::Message, Renderer> {
        use DesktopMsg::*;
        let Self {
            desktop_conf,
            ls_desktop_items,
            selected_desktop_item,
            ..
        } = self;
        
        let desktop_conf = desktop_conf.borrow();
        let item_conf = &desktop_conf.desktop_item_conf;
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
                let icon: Element<Self::Message, Renderer> = if let Some(icon_path) = &item.icon_path {
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
                    .on_press(DesktopItemClicked(idx))
                    .on_double_click(LaunchDesktopItem(idx));
                if let Some(curr_idx) = *selected_desktop_item {
                    if curr_idx == idx {
                        btn = btn.style(CustomButton::Selected);
                    } else {
                        btn = btn.style(CustomButton::Transparent);
                    }
                } else {
                    btn = btn.style(CustomButton::Transparent);
                }

                let tooltip_btn: Element<Self::Message, Renderer> = if item_conf.show_tooltip {
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