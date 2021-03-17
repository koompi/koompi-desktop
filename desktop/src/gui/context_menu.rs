use iced_wgpu::Renderer;
use iced_winit::{
    Command, Container, Element, Length, Program, Button, Text, Column, button, 
    Row, Icon, Icons, Space, Rule
};
use crate::styles::{CustomButton, ContainerFill, HOVERED};

#[derive(Debug)]
pub struct ContextMenu {
    menu_items: Vec<MenuItemNode>,
}

#[derive(Debug, Clone)]
pub struct MenuItemNode {
    state: button::State,
    title: String,
    selected: bool,
    is_showed: bool,
    has_underline: bool,
    submenu: Option<Vec<MenuItemNode>>,
    callback: Option<Message>,
}

impl MenuItemNode {
    pub fn new(title: &str, has_underline: bool, callback: Option<Message>, submenu: Option<Vec<MenuItemNode>>) -> Self {
        Self {
            submenu, callback, has_underline,
            title: title.to_owned(),
            state: button::State::new(),
            is_showed: false,
            selected: false,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum Message {
    ChangeBG,
    NewFolder,
    SortBy,
    DesktopView,
}

impl ContextMenu {
    pub fn new() -> Self {
        Self {
            menu_items: vec![
                MenuItemNode::new("New Folder", true, Some(Message::NewFolder), None),
                MenuItemNode::new("Change Desktop Background", false, Some(Message::ChangeBG), None),
                MenuItemNode::new("Sort By", true, Some(Message::SortBy), Some(vec![
                    MenuItemNode::new("Manual", true, None, None),
                    MenuItemNode::new("Name", false, None, None),
                    MenuItemNode::new("Type", false, None, None),
                    MenuItemNode::new("Date", false, None, None),
                ])),
                MenuItemNode::new("Desktop View", false, Some(Message::DesktopView), None),
            ]
        }
    }
}

impl Program for ContextMenu {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::ChangeBG => println!("change desktop background"),
            Message::NewFolder => println!("create new folder"),
            Message::SortBy => println!("change sort by field"),
            Message::DesktopView => println!("display desktop view configurations window"),
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let context_menu = self.menu_items.iter_mut()
            .fold(Column::new().padding(4), |mut column, item| {
                let mut content = Row::new().spacing(7).padding(5);
                if item.selected {
                    content = content.push(Icon::new(Icons::Check));
                }
                content = content.push(Text::new(&item.title));
                // let mut submenu = None;
                if let Some(submenu) = &item.submenu {
                    content = content
                        .push(Space::with_width(Length::Fill))
                        .push(Icon::new(Icons::AngleRight));
                    // submenu = menu(submenu);
                }
                let mut btn = Button::new(&mut item.state, content)
                    .width(Length::Fill)
                    .style(CustomButton::Transparent);
                if let Some(callback) = item.callback {
                    btn = btn.on_press(callback);
                }

                column = column.push(btn);
                if item.has_underline {
                    column.push(Rule::horizontal(10))
                } else {
                    column
                }

            });
        // let context_menu = menu(&mut self.menu_items);

        Container::new(context_menu)
            .width(Length::Fill)
            .height(Length::Fill)
            .style(ContainerFill(HOVERED))
            .into()
    }
}