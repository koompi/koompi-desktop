use std::{cell::RefCell, rc::Rc};
use crate::proxy_message::ProxyMessage;
use crate::configs::{
    DesktopConf, PersistentData,
    background_conf::BackgroundType,
    wallpaper_conf::Placement
};
use crate::background::WallpaperItem;
use super::styles::{CustomButton, CustomTooltip, CustomContainer, BACKGROUND};
use super::has_changed::HasChanged;
use iced::Image;
use iced_wgpu::Renderer;
use iced_winit::{
    winit, pick_list, button, scrollable, text_input, tooltip, Program, Command, Element, Row, Container, Clipboard,
    Text, Scrollable, Button, Space, Length, Align, Column, Application, TextInput, Tooltip, PickList, Grid, Color,
};
use winit::event_loop::EventLoopProxy;

#[derive(Debug)]
pub struct BackgroundConfigUI {
    proxy: EventLoopProxy<ProxyMessage>,
    bg_type_state: pick_list::State<BackgroundType>,
    desktop_conf: Rc<RefCell<DesktopConf>>,
    color_state: text_input::State,
    text: String,
    placement_state: pick_list::State<Placement>,
    wallpaper_items: Vec<(button::State, WallpaperItem)>,
    selected_wallpaper: Option<usize>,
    btn_apply_state: button::State,
    btn_add_state: button::State,
    scroll: scrollable::State,
    is_changed: bool,
}

#[derive(Debug, Clone)]
pub enum BackgroundConfMsg {
    BackgroundTypeChanged(BackgroundType),
    ColorChanged(String),
    PlacementChanged(Placement),
    WallpaperChanged(usize),
    AddWallpaperClicked,
    ApplyClicked,
}

impl Application for BackgroundConfigUI {
    type Flags = (EventLoopProxy<ProxyMessage>, Rc<RefCell<DesktopConf>>, Vec<WallpaperItem>, Option<usize>);

    fn new(flags: Self::Flags) -> (Self, Command<BackgroundConfMsg>) {
        (
            Self {
                proxy: flags.0,
                desktop_conf: flags.1,
                wallpaper_items: flags.2.into_iter().map(|item| (button::State::new(), item)).collect(),
                selected_wallpaper: flags.3,
                text: String::from("sample test"),
                bg_type_state: Default::default(),
                btn_add_state: Default::default(),
                btn_apply_state: Default::default(),
                color_state: text_input::State::focused(),
                is_changed: false,
                placement_state: Default::default(),
                scroll: Default::default(),
            },
            Command::none()
        )
    }

    fn title(&self) -> String {
        String::from("Desktop Background Configuration")
    }

    fn background_color(&self) -> Color {
        BACKGROUND
    }
}

impl Program for BackgroundConfigUI {
    type Message = BackgroundConfMsg;
    type Renderer = Renderer;
    type Clipboard = Clipboard;

    fn update(&mut self, msg: Self::Message, _clipboard: &mut Clipboard) -> Command<Self::Message> {
        use BackgroundConfMsg::*;

        let mut had_changed = false;
        let mut desktop_conf = self.desktop_conf.borrow_mut();
        let bg_conf = &mut desktop_conf.background_conf;
        let wallpaper_conf = &mut bg_conf.wallpaper_conf;

        match msg {
            BackgroundTypeChanged(val) => bg_conf.kind = val,
            ColorChanged(val) => self.text = val,
            PlacementChanged(val) => wallpaper_conf.placement = val,
            WallpaperChanged(idx) => {
                self.selected_wallpaper = Some(idx);
                if let Some((_, item)) = self.wallpaper_items.get(idx) {
                    wallpaper_conf.wallpaper_path = item.path.to_path_buf();
                }
            },
            AddWallpaperClicked => self.proxy.send_event(ProxyMessage::Bg(AddWallpaperClicked)).unwrap(),
            ApplyClicked => {
                let _ = desktop_conf.save();
                had_changed = true;
            }
        }
        self.is_changed = !had_changed;

        Command::none()
    }

    fn view(&mut self) -> Element<Self::Message, Renderer> {
        use BackgroundConfMsg::*;
        let Self {
            desktop_conf,
            bg_type_state,
            placement_state,
            wallpaper_items, 
            selected_wallpaper,
            btn_add_state,
            btn_apply_state,
            scroll,
            ..
        } = self;

        let desktop_conf = desktop_conf.borrow();
        let bg_conf = &desktop_conf.background_conf;
        let lb_bg = Text::new("Background:");
        let pl_bg = PickList::new(bg_type_state, &BackgroundType::ALL[..], Some(bg_conf.kind), BackgroundTypeChanged);
        let content: Element<_, _> = match bg_conf.kind {
            BackgroundType::Color => {
                let lb_color = Text::new("Color: ");
                let txt_color = TextInput::new(&mut self.color_state, "", &self.text, ColorChanged).padding(7);
                Row::new().spacing(15).align_items(Align::Center)
                    .push(lb_color)
                    .push(txt_color)
                    .into()
            },
            BackgroundType::Wallpaper => {
                let lb_placement = Text::new("Mode: ");
                let pl_placement = PickList::new(placement_state, &Placement::ALL[..], Some(bg_conf.wallpaper_conf.placement), PlacementChanged);
                let sec_selected_wallpaper: Element<_, _> = if let Some(selected) = *selected_wallpaper {
                    if let Some((_, item)) = wallpaper_items.get(selected) {
                        let image = Image::new(item.path.to_path_buf()).width(Length::Units(200));
                        let mut row = Row::new().padding(10).spacing(20).align_items(Align::Center).push(image);
                        if let Some(name) = &item.name {
                            row = row.push(Text::new(name).size(17))
                        }
                        
                        row.into()
                    } else {
                        Row::new().into()
                    }
                } else {
                    Row::new().into()
                };

                let wallpaper_grid = wallpaper_items.iter_mut().enumerate().fold(Grid::new().width(Length::Fill).column_width(175).padding(7).spacing(10), |grid, (idx, (state, item))| {
                    let mut btn = Button::new(state, Image::new(item.path.to_path_buf()).width(Length::Fill)).padding(7).width(Length::Units(165)).on_press(WallpaperChanged(idx));
                    btn = if let Some(selected) = *selected_wallpaper {
                        if idx == selected {
                            btn.style(CustomButton::Selected)
                        } else {
                            btn.style(CustomButton::Text)
                        }
                    } else {
                        btn.style(CustomButton::Text)
                    };

                    let content: Element<_, _> = if let Some(name) = &item.name {
                        Tooltip::new(btn, name, tooltip::Position::FollowCursor).size(13).gap(5).padding(5).style(CustomTooltip).into()
                    } else {
                        btn.into()
                    };
        
                    grid.push(Container::new(content).height(Length::Fill).center_x().center_y())
                });
        
                Column::new().spacing(15)
                    .push(
                        Row::new().spacing(15).align_items(Align::Center)
                        .push(lb_placement)
                        .push(pl_placement)
                    )
                    .push(sec_selected_wallpaper)
                    .push(Container::new(wallpaper_grid).center_x().center_y().style(CustomContainer::Foreground))
                    .into()
            }
        };
        let btn_add = Button::new(btn_add_state, Text::new("  Choose New ")).on_press(AddWallpaperClicked).style(CustomButton::Default);
        let mut btn_apply = Button::new(btn_apply_state, Text::new("  Apply  ")).style(CustomButton::Primary);
        if self.is_changed {
            btn_apply = btn_apply.on_press(ApplyClicked)
        }

        Column::new().spacing(15).padding(20)
            .push(Row::new().spacing(10).align_items(Align::Center).push(lb_bg).push(pl_bg))
            .push(
                Scrollable::new(scroll).width(Length::Fill).height(Length::Fill).scroller_width(4).scrollbar_width(4).spacing(15)
                .push(content)
            )
            .push(Row::new().spacing(15).push(btn_add).push(Space::with_width(Length::Fill)).push(btn_apply))
            .into()
    }
}

impl HasChanged for BackgroundConfigUI {
    fn has_changed(&self) -> bool {
        self.is_changed
    }
} 