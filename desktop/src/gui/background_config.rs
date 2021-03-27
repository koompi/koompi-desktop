use crate::configs::{
    background_conf::{BackgroundConf, BackgroundType},
};
use crate::background::WallpaperItem;
use super::color_config::{ColorConfigUI, ColorConfigMsg};
use super::wallpaper_config::{WallpaperConfigUI, WallpaperConfigMsg};
use super::styles::CustomButton;
use iced_winit::{
    pick_list, button, scrollable, PickList, Program, Command, Element, Row,
    Text, Scrollable, Button, Space, Length, Align, Column, Application, 
};
use iced_wgpu::{Renderer};

#[derive(Debug, Clone)]
pub struct BackgroundConfigUI {
    bg_type_state: pick_list::State<BackgroundType>,
    bg_conf: BackgroundConf,
    dyn_config_ui: DynConfigUI,
    wallpaper_items: Vec<WallpaperItem>,
    btn_apply_state: button::State,
    scroll: scrollable::State,
}

#[derive(Debug, Clone)]
pub enum DynConfigUI {
    ColorConfig(ColorConfigUI),
    WallpaperConfig(WallpaperConfigUI),

}
#[derive(Debug, Clone)]
pub enum BackgroundConfMsg {
    BackgroundTypeChanged(BackgroundType),
    ColorMsg(ColorConfigMsg),
    WallpaperMsg(WallpaperConfigMsg),
    ApplyClicked,
}

impl Application for BackgroundConfigUI {
    type Flags = (BackgroundConf, Vec<WallpaperItem>);

    fn new(flags: Self::Flags) -> (Self, Command<BackgroundConfMsg>) {
        use DynConfigUI::*;
        (
            Self {
                dyn_config_ui: match flags.0.kind {
                    BackgroundType::Color => ColorConfig(ColorConfigUI::new(flags.0.color_background.to_owned())),
                    BackgroundType::Wallpaper => WallpaperConfig(WallpaperConfigUI::new(flags.0.wallpaper_conf.to_owned(), flags.1.to_owned()))
                },
                bg_conf: flags.0,
                wallpaper_items: flags.1,
                scroll: scrollable::State::new(),
                btn_apply_state: button::State::new(),
                bg_type_state: pick_list::State::default()
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

    fn update(&mut self, msg: Self::Message) -> Command<Self::Message> {
        let Self {
            dyn_config_ui,
            bg_conf,
            wallpaper_items,
            ..
        } = self;
        use BackgroundConfMsg::*;
        match msg {
            BackgroundTypeChanged(val) => {
                use DynConfigUI::*;

                bg_conf.kind = val;
                self.dyn_config_ui = match val {
                    BackgroundType::Color => ColorConfig(ColorConfigUI::new(bg_conf.color_background)),
                    BackgroundType::Wallpaper => WallpaperConfig(WallpaperConfigUI::new(bg_conf.wallpaper_conf.to_owned(), wallpaper_items.to_owned()))
                };
            },
            ColorMsg(color_msg) => if let DynConfigUI::ColorConfig(color_ui) = dyn_config_ui {
                color_ui.update(color_msg)
            },
            WallpaperMsg(wallpaper_msg) => if let DynConfigUI::WallpaperConfig(wallpaper_ui) = dyn_config_ui {
                wallpaper_ui.update(wallpaper_msg)
            },
            ApplyClicked => println!("apply clicked")
        }
        Command::none()
    }

    fn view(&mut self) -> Element<Self::Message, Renderer> {
        use BackgroundConfMsg::*;
        let Self {
            bg_conf,
            bg_type_state,
            dyn_config_ui,
            btn_apply_state,
            scroll,
            ..
        } = self;

        let lb_bg = Text::new("Background:");
        let pl_bg = PickList::new(bg_type_state, &BackgroundType::ALL[..], Some(bg_conf.kind), BackgroundTypeChanged);
        let content = match dyn_config_ui {
            DynConfigUI::ColorConfig(color_ui) => color_ui.view().map(|msg| ColorMsg(msg)),
            DynConfigUI::WallpaperConfig(wallpaper_ui) => wallpaper_ui.view().map(|msg| WallpaperMsg(msg))
        };
        let btn_apply = Button::new(btn_apply_state, Text::new("  Apply  ")).on_press(ApplyClicked).style(CustomButton::Primary);

        Column::new().spacing(15).padding(15)
            .push(
                Scrollable::new(scroll).scroller_width(4).scrollbar_width(4).spacing(15)
                .push(
                    Row::new().spacing(10).align_items(Align::Center).push(lb_bg).push(pl_bg)
                )
                .push(content)
            )
            .push(Space::with_height(Length::Fill))
            .push(Row::new().push(Space::with_width(Length::Fill)).push(btn_apply))
            .into()

    }
}