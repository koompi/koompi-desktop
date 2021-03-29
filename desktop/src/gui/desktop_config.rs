use crate::configs::{
    DesktopConf,
    desktop_item_conf::{Arrangement, Sorting, DesktopItemConf}
};
use iced_winit::{
    pick_list, PickList, slider, Slider, Application, Program, Command, Element,
    Text, Checkbox, scrollable, Scrollable, Column, Row, Length,
};
use iced_wgpu::{Renderer};

#[derive(Debug, Clone, Default)]
pub struct DesktopConfigUI {
    desktop_conf: DesktopConf,
    arrangement_state: pick_list::State<Arrangement>,
    sort_by_state: pick_list::State<Sorting>,
    icon_size_state: slider::State,
    grid_spacing_state: slider::State,
    scroll: scrollable::State,
}

#[derive(Debug, Clone)]
pub enum DesktopConfigMsg {
    ArrangementChanged(Arrangement),
    SortingChanged(Sorting),
    IconSizeChanged(u16),
    GridSpacingChanged(u16),
    SortDescToggled(bool),
    ShowTooltipToggled(bool),
}

impl Application for DesktopConfigUI {
    type Flags = DesktopConf;

    fn new(flags: Self::Flags) -> (Self, Command<DesktopConfigMsg>) {
        (
            Self {
                desktop_conf: flags,
                ..Self::default()
            },
            Command::none()
        )
    }

    fn title(&self) -> String {
        String::from("Desktop")
    }
}

impl Program for DesktopConfigUI {
    type Message = DesktopConfigMsg;
    type Renderer = Renderer;

    fn update(&mut self, msg: Self::Message) -> Command<Self::Message> { 
        use DesktopConfigMsg::*;
        let desktop_item_conf = &mut self.desktop_conf.desktop_item_conf;
        match msg {
            ArrangementChanged(val) => desktop_item_conf.arrangement = val,
            SortingChanged(val) => desktop_item_conf.sorting = val,
            IconSizeChanged(val) => desktop_item_conf.icon_size = val,
            GridSpacingChanged(val) => desktop_item_conf.grid_spacing = val,
            SortDescToggled(is_checked) => desktop_item_conf.sort_descending = is_checked,
            ShowTooltipToggled(is_checked) => desktop_item_conf.show_tooltip = is_checked
        }
        Command::none()
    }

    fn view(&mut self) -> Element<Self::Message, Renderer> {
        use DesktopConfigMsg::*;
        let Self {
            desktop_conf,
            arrangement_state,
            sort_by_state,
            icon_size_state,
            grid_spacing_state,
            scroll,
        } = self;

        let desktop_item_conf = &desktop_conf.desktop_item_conf;

        let lb_sort_by = Text::new("Sort by:");
        let pl_sort_by = PickList::new(sort_by_state, &Sorting::ALL[..], Some(desktop_item_conf.sorting), SortingChanged);
        let lb_arragement = Text::new("Arrangement:");
        let pl_arragement = PickList::new(arrangement_state, &Arrangement::ALL[..], Some(desktop_item_conf.arrangement), ArrangementChanged);
        let lb_icon_size = Text::new(format!("Icon size: {}x{}", desktop_item_conf.icon_size, desktop_item_conf.icon_size));
        let sl_icon_size = Slider::new(icon_size_state, DesktopItemConf::MIN_ICON_SIZE..=DesktopItemConf::MAX_ICON_SIZE, desktop_item_conf.icon_size, IconSizeChanged).step(2);
        let lb_grid_spacing = Text::new("Grid Spacing:");
        let sl_grid_spacing = Slider::new(grid_spacing_state, DesktopItemConf::MIN_GRID_SPACING..=DesktopItemConf::MAX_GRID_SPACING, desktop_item_conf.grid_spacing, GridSpacingChanged);
        let chb_sort_desc = Checkbox::new(desktop_item_conf.sort_descending, "Sort descending", SortDescToggled);
        let chb_show_tooltip = Checkbox::new(desktop_item_conf.show_tooltip, "Show Tooltip", ShowTooltipToggled);

        let pl_sec_lb = Column::new().spacing(15)
            .push(lb_sort_by)
            .push(lb_arragement);
        let pl_sec = Column::new().spacing(7)
            .push(pl_sort_by)
            .push(pl_arragement);

        Scrollable::new(scroll).scroller_width(4).scrollbar_width(4).spacing(10).padding(15).width(Length::Fill).height(Length::Fill)
            .push(
                Row::new().spacing(10).push(pl_sec_lb).push(pl_sec)
            )
            .push(lb_icon_size)
            .push(sl_icon_size)
            .push(lb_grid_spacing)
            .push(sl_grid_spacing)
            .push(chb_sort_desc)
            .push(chb_show_tooltip)
            .into()

    }
}