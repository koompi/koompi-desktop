use std::{cell::RefCell, rc::Rc};
use crate::configs::{
    DesktopConf,
    background_conf::BackgroundType,
    desktop_item_conf::Arrangement,
};
use crate::desktop_item::DesktopItem;
use super::styles::{CustomButton, CustomTooltip};
use iced::{Svg, Image};
use iced_wgpu::Renderer;
use iced_winit::{
    Color, Command, Container, Element, Length, Program, Grid, Button, Text, Column, button, keyboard, Row, 
    Align, HorizontalAlignment, Tooltip, tooltip, Application, Event, Subscription, Clipboard, Stack, mouse,
};
use tauri_dialog::{DialogBuilder, DialogStyle};

#[derive(Debug)]
pub struct Desktop {
    size: (u32, u32),
    desktop_conf: Rc<RefCell<DesktopConf>>,
    ls_desktop_items_state: Vec<button::State>,
    ls_desktop_items: Rc<RefCell<Vec<DesktopItem>>>,
    selected_desktop_item: Option<usize>,
}

#[derive(Debug, Clone)]
pub enum DesktopMsg {
    DesktopItemClicked(usize),
    LaunchDesktopItem(usize),
    DesktopItemRightClicked(usize),
    WinitEvent(Event)
}

impl Desktop {
    fn handle_double_clicked(&self, idx: usize) {
        let desktop_items = self.ls_desktop_items.borrow();

        if let Some(desktop_item) = desktop_items.get(idx) {
            if let Err(err) = desktop_item.exec_default_app() {
                let _ = DialogBuilder::new().title("Error")
                    .message(&format!("{}", err))
                    .style(DialogStyle::Error)
                    .build().show();
            }
        }
    }
}

impl Application for Desktop {
    type Flags = ((u32, u32), Rc<RefCell<DesktopConf>>, usize, Rc<RefCell<Vec<DesktopItem>>>);

    fn new(flags: Self::Flags) -> (Self, Command<DesktopMsg>) { 
        (
            Self {
                size: flags.0,
                desktop_conf: flags.1,
                ls_desktop_items_state: vec![button::State::new(); flags.2],
                ls_desktop_items: flags.3,
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
        let desktop_items = self.ls_desktop_items.borrow();

        match message {
            DesktopItemClicked(idx) => self.selected_desktop_item = Some(idx),
            LaunchDesktopItem(idx) => self.handle_double_clicked(idx),
            DesktopItemRightClicked(idx) => println!("right click on {}", idx),
            WinitEvent(event) => {
                match event {
                    Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => self.selected_desktop_item = None, 
                    Event::Keyboard(key_event) => match key_event {
                        keyboard::Event::CharacterReceived('\r') => if let Some(idx) = self.selected_desktop_item {
                            self.handle_double_clicked(idx);
                        },
                        keyboard::Event::KeyPressed { key_code, .. } => match key_code {
                            keyboard::KeyCode::Right => if let Some(idx) = &mut self.selected_desktop_item {
                                if *idx<desktop_items.len()-1 {
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
                                    *idx = desktop_items.len()-1;
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
            ls_desktop_items_state,
            ls_desktop_items,
            selected_desktop_item,
            ..
        } = self;
        
        let desktop_items = ls_desktop_items.borrow();
        let desktop_conf = desktop_conf.borrow();
        let bg_conf = &desktop_conf.background_conf;
        let item_conf = &desktop_conf.desktop_item_conf;

        let grid_spacing = item_conf.grid_spacing;
        let item_size = item_conf.icon_size + 40;
        let item_size_spacing = item_size + grid_spacing;
        let mut grid = Grid::new().column_width(item_size_spacing).padding(20).spacing(grid_spacing);
        if let Arrangement::Columns = item_conf.arrangement {
            let items_in_height = item_size_spacing as usize*desktop_items.len();
            grid = grid.columns((items_in_height as f32/self.size.1 as f32).ceil() as usize);
        }

        let desktop_grid = ls_desktop_items_state.iter_mut().zip(desktop_items.iter()).enumerate().fold(grid, |grid, (idx, (state, item))| {
            let mut icon = Row::new();
            if let Some(icon_path) = &item.icon_path {
                if let Some(extension) = icon_path.extension() {
                    icon = icon.push::<Element<_, _>>(if extension == "svg" || extension == "svgz" {
                        Svg::from_path(icon_path).width(Length::Units(item_conf.icon_size)).height(Length::Units(item_conf.icon_size)).into()
                    } else {
                        Image::new(icon_path).width(Length::Units(item_conf.icon_size)).height(Length::Units(item_conf.icon_size)).into()
                    });
                }
            }
            let con = Column::new().spacing(10).align_items(Align::Center)
                .push(icon)
                .push(Text::new(item.name.as_ref().unwrap_or(&"Unknown name".to_string())).horizontal_alignment(HorizontalAlignment::Center));

            let mut btn = Button::new(state, con)
                .width(Length::Units(item_size))
                .padding(7)
                .on_press(DesktopItemClicked(idx))
                .on_double_click(LaunchDesktopItem(idx))
                .on_right_click(DesktopItemRightClicked(idx));
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

        let desktop_sec: Element<_, _> = match bg_conf.kind {
            BackgroundType::Color => desktop_grid.into(),
            BackgroundType::Wallpaper => {
                let wallpaper_path = bg_conf.wallpaper_conf.wallpaper_path.to_path_buf();
                if wallpaper_path.exists() && wallpaper_path.is_file() && wallpaper_path.is_absolute() {
                    Stack::new()
                    .push(Image::new(wallpaper_path).width(Length::Fill).height(Length::Fill), None)
                    .push(desktop_grid, None)
                    .into()
                } else {
                    desktop_grid.into()
                }
            }
        };
        
        Container::new(desktop_sec).width(Length::Fill).height(Length::Fill).into()
    }
}