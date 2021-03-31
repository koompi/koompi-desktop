use std::{cell::RefCell, rc::Rc};
use crate::configs::{
    DesktopConf, PersistentData,
    background_conf::BackgroundType,
    wallpaper_conf::Placement
};
use crate::background::WallpaperItem;
use super::styles::CustomButton;
use super::has_changed::HasChanged;
use iced::Image;
use iced_wgpu::Renderer;
use iced_winit::{
    pick_list, button, scrollable, text_input, PickList, Program, Command, Element, Row, Container, Grid, Clipboard,
    Text, Scrollable, Button, Space, Length, Align, Column, Application, TextInput, HorizontalAlignment,
};

#[derive(Debug, Clone, Default)]
pub struct BackgroundConfigUI {
    bg_type_state: pick_list::State<BackgroundType>,
    desktop_conf: Rc<RefCell<DesktopConf>>,
    color_state: text_input::State,
    text: String,
    placement_state: pick_list::State<Placement>,
    wallpaper_items: Vec<(button::State, WallpaperItem)>,
    selected_wallpaper: Option<usize>,
    btn_apply_state: button::State,
    scroll: scrollable::State,
    is_changed: bool,
}

#[derive(Debug, Clone)]
pub enum BackgroundConfMsg {
    BackgroundTypeChanged(BackgroundType),
    ColorChanged(String),
    PlacementChanged(Placement),
    WallpaperChanged(usize),
    ApplyClicked,
}

impl Application for BackgroundConfigUI {
    type Flags = (Rc<RefCell<DesktopConf>>, Vec<WallpaperItem>);

    fn new(flags: Self::Flags) -> (Self, Command<BackgroundConfMsg>) {
        (
            Self {
                desktop_conf: flags.0,
                wallpaper_items: flags.1.into_iter().map(|item| (button::State::new(), item)).collect(),
                selected_wallpaper: None,
                text: String::from("sample test"),
                ..Self::default()
            },
            Command::none()
        )
    }

    fn title(&self) -> String {
        String::from("Desktop Background Configuration")
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
                let lb_placement = Text::new("Placement: ");
                let pl_placement = PickList::new(placement_state, &Placement::ALL[..], Some(bg_conf.wallpaper_conf.placement), PlacementChanged);
                let wallpaper_grid = wallpaper_items.iter_mut().enumerate().fold(Grid::new().width(Length::Fill).column_width(140).padding(15).spacing(15), |grid, (idx, (state, item))| {
                    let name = Text::new(item.name.as_ref().map(|name| name.as_str()).unwrap_or("Unknown name")).horizontal_alignment(HorizontalAlignment::Center);
                    let image = Image::new(item.path.to_path_buf()).width(Length::Units(227));
                    let mut btn = Button::new(state, Column::new().spacing(10)
                        .push(image)
                        .push(name)
                    ).padding(7).width(Length::Units(120)).on_press(WallpaperChanged(idx));
                    btn = if let Some(selected) = *selected_wallpaper {
                        if idx == selected {
                            btn.style(CustomButton::Selected)
                        } else {
                            btn.style(CustomButton::Text)
                        }
                    } else {
                        btn.style(CustomButton::Text)
                    };
        
                    grid.push(
                        Container::new(btn).center_x().center_y()
                    )
                });
        
                Column::new().spacing(15)
                    .push(
                        Row::new().spacing(15).align_items(Align::Center)
                        .push(lb_placement)
                        .push(pl_placement)
                    )
                    .push(wallpaper_grid)
                    .into()
            }
        };
        let mut btn_apply = Button::new(btn_apply_state, Text::new("  Apply  ")).style(CustomButton::Primary);
        if self.is_changed {
            btn_apply = btn_apply.on_press(ApplyClicked)
        }

        Column::new().spacing(15).padding(15)
            .push(Row::new().spacing(10).align_items(Align::Center).push(lb_bg).push(pl_bg))
            .push(
                Scrollable::new(scroll).width(Length::Fill).height(Length::Fill).scroller_width(4).scrollbar_width(4).spacing(15)
                .push(content)
            )
            .push(Row::new().push(Space::with_width(Length::Fill)).push(btn_apply))
            .into()

    }
}

impl HasChanged for BackgroundConfigUI {
    fn has_changed(&self) -> bool {
        self.is_changed
    }
}