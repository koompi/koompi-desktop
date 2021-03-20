use crate::configs::{
    desktop_item_conf::{Arrangement, Sorting, DesktopItemConf}
};
use iced_winit::{
    pick_list, PickList, slider, Slider, Application, Program, Command, Element,
    Text, Checkbox, scrollable, Scrollable, Column, Row, Length,
};
use iced_wgpu::{Renderer};

#[derive(Debug, Clone, Default)]
pub struct DesktopConfigUI {
    arrangement_state: pick_list::State<Arrangement>,
    arrangement: Option<Arrangement>,
    sort_by_state: pick_list::State<Sorting>,
    sort_by: Option<Sorting>,
    icon_size_state: slider::State,
    icon_size: u16,
    grid_spacing_state: slider::State,
    grid_spacing: u16,
    sort_desc: bool,
    show_tooltip: bool,
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
    type Flags = DesktopItemConf;

    fn new(flags: Self::Flags) -> (Self, Command<DesktopConfigMsg>) {
        (
            Self {
                arrangement: Some(flags.arrangement),
                sort_by: Some(flags.sorting),
                icon_size: flags.icon_size,
                grid_spacing: flags.grid_spacing,
                sort_desc: flags.sort_descending,
                show_tooltip: flags.show_tooltip,
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
        match msg {
            ArrangementChanged(val) => self.arrangement = Some(val),
            SortingChanged(val) => self.sort_by = Some(val),
            IconSizeChanged(val) => self.icon_size = val,
            GridSpacingChanged(val) => self.grid_spacing = val,
            SortDescToggled(is_checked) => self.sort_desc = is_checked,
            ShowTooltipToggled(is_checked) => self.show_tooltip = is_checked
        }
        Command::none()
    }

    fn view(&mut self) -> Element<Self::Message, Renderer> {
        use DesktopConfigMsg::*;
        let Self {
            arrangement_state,
            arrangement,
            sort_by_state,
            sort_by,
            icon_size_state,
            icon_size,
            grid_spacing_state,
            grid_spacing,
            sort_desc,
            show_tooltip,
            scroll,
        } = self;

        let lb_sort_by = Text::new("Sort by:");
        let pl_sort_by = PickList::new(sort_by_state, &Sorting::ALL[..], *sort_by, SortingChanged);
        let lb_arragement = Text::new("Arrangement:");
        let pl_arragement = PickList::new(arrangement_state, &Arrangement::ALL[..], *arrangement, ArrangementChanged);
        let lb_icon_size = Text::new(format!("Icon size: {}x{}", icon_size, icon_size));
        let sl_icon_size = Slider::new(icon_size_state, DesktopItemConf::MIN_ICON_SIZE..=DesktopItemConf::MAX_ICON_SIZE, *icon_size, IconSizeChanged).step(2);
        let lb_grid_spacing = Text::new("Grid Spacing:");
        let sl_grid_spacing = Slider::new(grid_spacing_state, DesktopItemConf::MIN_GRID_SPACING..=DesktopItemConf::MAX_GRID_SPACING, *grid_spacing, GridSpacingChanged);
        let chb_sort_desc = Checkbox::new(*sort_desc, "Sort descending", SortDescToggled);
        let chb_show_tooltip = Checkbox::new(*show_tooltip, "Show Tooltip", ShowTooltipToggled);

        let pl_sec_lb = Column::new().spacing(15)
            .push(lb_sort_by)
            .push(lb_arragement);
        let pl_sec = Column::new().spacing(5)
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