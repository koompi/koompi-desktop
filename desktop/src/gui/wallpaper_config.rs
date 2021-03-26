use iced_wgpu::{
    Renderer
};
use crate::background::WallpaperItem;
use crate::configs::wallpaper_conf::{WallpaperConf, Placement};
use super::styles::CustomButton;
use iced_winit::{
    pick_list, button, Element, Text, PickList, Row, Button, Grid, Length, Container, Image, Column, Align,
};

#[derive(Debug, Clone, Default)]
pub struct WallpaperConfigUI {
    placement_state: pick_list::State<Placement>,
    wallpaper_conf: WallpaperConf,
    wallpaper_items: Vec<(button::State, WallpaperItem)>,
    selected_wallpaper: Option<usize>,
}

#[derive(Debug, Clone)]
pub enum WallpaperConfigMsg {
    PlacementChanged(Placement),
    WallpaperChanged(usize),
}

impl WallpaperConfigUI {
    pub fn new(wallpaper_conf: WallpaperConf, wallpaper_items: Vec<WallpaperItem>) -> Self {
        Self {
            selected_wallpaper: wallpaper_items.iter().position(|item| item.path == wallpaper_conf.wallpaper_path),
            wallpaper_items: wallpaper_items.into_iter().map(|item| (button::State::new(), item)).collect(),
            wallpaper_conf,
            ..Self::default()
        }
    }

    pub fn update(&mut self, msg: WallpaperConfigMsg) {
        use WallpaperConfigMsg::*;
        match msg {
            PlacementChanged(val) => self.wallpaper_conf.placement = val,
            WallpaperChanged(idx) => {
                self.selected_wallpaper = Some(idx);
                self.wallpaper_conf.wallpaper_path = self.wallpaper_items[idx].1.path.to_path_buf();
            }
        }
    }

    pub fn view(&mut self) -> Element<WallpaperConfigMsg, Renderer> {
        use WallpaperConfigMsg::*;
        let Self {
            wallpaper_conf,
            placement_state,
            wallpaper_items,
            selected_wallpaper,
        } = self;
        
        let lb_placement = Text::new("Placement: ");
        let pl_placement = PickList::new(placement_state, &Placement::ALL[..], Some(wallpaper_conf.placement), PlacementChanged);
        let wallpaper_grid = wallpaper_items.iter_mut().enumerate().fold(Grid::new().column_width(140).padding(15).spacing(15), |grid, (idx, (state, item))| {
            let name = Text::new(item.name.as_ref().map(|name| name.as_str()).unwrap_or("Unknown name"));
            let image = Image::new(item.path.to_path_buf()).width(Length::Units(100)).height(Length::Units(60));
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
}

