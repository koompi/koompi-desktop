use std::{cell::RefCell, rc::Rc};
use crate::proxy_message::ProxyMessage;
use libkoompi::desktop::{
    PersistentData, 
    configs::{
        DesktopConf,
        desktop_item_conf::{Arrangement, Sorting, DesktopItemConf}
    }
};
use super::styles::{CustomButton, BACKGROUND, CustomSelect, CustomSlider, CustomCheckbox};
use super::has_changed::HasChanged;
use iced_winit::{
    winit, pick_list, button, scrollable, slider, PickList, Slider, Program, Command, Element, Color,
    Text, Checkbox, Scrollable, Column, Row, Length, Button, Space, Clipboard, Application, Align,
}; 
use winit::event_loop::EventLoopProxy;
use iced_wgpu::Renderer;

#[derive(Debug)]
pub struct DesktopConfigUI {
    desktop_conf: Rc<RefCell<DesktopConf>>,
    arrangement_state: pick_list::State<Arrangement>,
    sort_by_state: pick_list::State<Sorting>,
    icon_size_state: slider::State,
    grid_spacing_state: slider::State,
    btn_apply_state: button::State,
    is_changed: bool,
    scroll: scrollable::State,
    proxy: EventLoopProxy<ProxyMessage>,
}

#[derive(Debug, Clone)]
pub enum DesktopConfigMsg {
    ArrangementChanged(Arrangement),
    SortingChanged(Sorting),
    IconSizeChanged(u16),
    GridSpacingChanged(u16),
    SortDescToggled(bool),
    ShowTooltipToggled(bool),
    ApplyClicked,
}

impl Application for DesktopConfigUI {
    type Flags = (EventLoopProxy<ProxyMessage>, Rc<RefCell<DesktopConf>>);

    fn new(flags: Self::Flags) -> (Self, Command<DesktopConfigMsg>) {
        (
            Self {
                proxy: flags.0,
                desktop_conf: flags.1,
                arrangement_state: Default::default(),
                sort_by_state: Default::default(),
                icon_size_state: Default::default(),
                grid_spacing_state: Default::default(),
                btn_apply_state: Default::default(),
                scroll: Default::default(),
                is_changed: false,
            },
            Command::none()
        )
    }

    fn title(&self) -> String {
        String::from("Desktop")
    }

    fn background_color(&self) -> Color {
        BACKGROUND
    }
}

impl Program for DesktopConfigUI {
    type Message = DesktopConfigMsg;
    type Renderer = Renderer;
    type Clipboard = Clipboard;

    fn update(&mut self, msg: Self::Message, _clipboard: &mut Clipboard) -> Command<Self::Message> { 
        use DesktopConfigMsg::*;
        let mut had_changed = false;
        let mut desktop_conf = self.desktop_conf.borrow_mut();
        let desktop_item_conf = &mut desktop_conf.desktop_item_conf;

        match msg {
            ArrangementChanged(val) => desktop_item_conf.arrangement = val,
            SortingChanged(val) => {
                desktop_item_conf.sorting = val;
                self.proxy.send_event(ProxyMessage::DesktopConf(SortingChanged(val))).unwrap();
            },
            IconSizeChanged(val) => desktop_item_conf.icon_size = val,
            GridSpacingChanged(val) => desktop_item_conf.grid_spacing = val,
            SortDescToggled(is_checked) => {
                desktop_item_conf.sort_descending = is_checked;
                self.proxy.send_event(ProxyMessage::DesktopConf(SortDescToggled(is_checked))).unwrap();
            },
            ShowTooltipToggled(is_checked) => desktop_item_conf.show_tooltip = is_checked,
            ApplyClicked => {
                let _ = desktop_conf.save();
                had_changed = true;
            }
        }
        self.is_changed = !had_changed;

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
            btn_apply_state,
            scroll,
            ..
        } = self;

        let desktop_conf = desktop_conf.borrow();
        let desktop_item_conf = &desktop_conf.desktop_item_conf;

        let lb_sort_by = Text::new("Sort by:");
        let pl_sort_by = PickList::new(sort_by_state, &Sorting::ALL[..], Some(desktop_item_conf.sorting), SortingChanged).style(CustomSelect);
        let lb_arragement = Text::new("Arrangement:");
        let pl_arragement = PickList::new(arrangement_state, &Arrangement::ALL[..], Some(desktop_item_conf.arrangement), ArrangementChanged).style(CustomSelect);
        let lb_icon_size = Text::new(format!("Icon size: {}x{}px", desktop_item_conf.icon_size, desktop_item_conf.icon_size));
        let sl_icon_size = Slider::new(icon_size_state, DesktopItemConf::MIN_ICON_SIZE..=DesktopItemConf::MAX_ICON_SIZE, desktop_item_conf.icon_size, IconSizeChanged).style(CustomSlider);
        let lb_grid_spacing = Text::new(format!("Grid spacing: {}px", desktop_item_conf.grid_spacing));
        let sl_grid_spacing = Slider::new(grid_spacing_state, DesktopItemConf::MIN_GRID_SPACING..=DesktopItemConf::MAX_GRID_SPACING, desktop_item_conf.grid_spacing, GridSpacingChanged).style(CustomSlider);
        let chb_sort_desc = Checkbox::new(desktop_item_conf.sort_descending, "Sort descending", SortDescToggled).style(CustomCheckbox);
        let chb_show_tooltip = Checkbox::new(desktop_item_conf.show_tooltip, "Show tooltip", ShowTooltipToggled).style(CustomCheckbox);

        let pl_sec_lb = Column::new().spacing(12)
            .push(lb_sort_by)
            .push(lb_arragement);
        let pl_sec = Column::new().spacing(7)
            .push(pl_sort_by)
            .push(pl_arragement);

        let scrollable = Scrollable::new(scroll).scroller_width(4).scrollbar_width(4).spacing(10)
            .push(
                Row::new().spacing(10).align_items(Align::Center).push(pl_sec_lb).push(pl_sec)
            )
            .push(lb_icon_size)
            .push(sl_icon_size)
            .push(lb_grid_spacing)
            .push(sl_grid_spacing)
            .push(chb_sort_desc)
            .push(chb_show_tooltip);

        let mut btn_apply = Button::new(btn_apply_state, Text::new("  Apply  ")).style(CustomButton::Primary);
        if self.is_changed {
            btn_apply = btn_apply.on_press(ApplyClicked)
        }

        Column::new().padding(15).width(Length::Fill)
            .push(scrollable)
            .push(Space::with_height(Length::Fill))
            .push(Row::new().push(Space::with_width(Length::Fill)).push(btn_apply))
            .into()
    }
}

impl HasChanged for DesktopConfigUI {
    fn has_changed(&self) -> bool {
        self.is_changed
    }
}