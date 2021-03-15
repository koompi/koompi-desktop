use iced_wgpu::Renderer;
use iced_winit::{
    Command, Container, Element, Length, Program, Button, Text, Column, button, 
    Row, Icon, Icons, Space, Color,
};
use crate::styles::{CustomButton, ContainerFill};

#[derive(Debug)]
pub struct ContextMenu {
    menu_items: Vec<MenuItemNode>,
}

#[derive(Debug, Clone)]
pub struct MenuItemNode {
    pub selected: bool,
    pub icon: Icons,
    pub state: button::State,
    pub title: String,
    pub submenu: Option<Vec<MenuItemNode>>,
}

impl MenuItemNode {
    pub fn new(icon: Icons, title: &str, submenu: Option<Vec<MenuItemNode>>) -> Self {
        Self {
            submenu, icon,
            title: title.to_owned(),
            state: button::State::new(),
            selected: false
        }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    MenuItemSelected(usize),
}

impl ContextMenu {
    pub fn new() -> Self {
        Self {
            menu_items: vec![
                MenuItemNode::new(Icons::Desktop, "Configure desktop and wallpaper", None),
                MenuItemNode::new(Icons::Plus, "Create new", Some(
                    vec![
                        MenuItemNode::new(Icons::File, "Text document", None),
                        MenuItemNode::new(Icons::FileCsv, "CSV Sheet", None),
                    ]
                )),
                MenuItemNode::new(Icons::HandPointingUp, "Paste", None),
            ]
        }
    }
}

impl Program for ContextMenu {
    type Renderer = Renderer;
    type Message = Message;

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::MenuItemSelected(idx) => if let Some(item) = self.menu_items.get_mut(idx) {
                item.selected = true;
            }
        }

        Command::none()
    }

    fn view(&mut self) -> Element<Message, Renderer> {
        let context_menu = self.menu_items.iter_mut().enumerate()
            .fold(Column::new(), |column, (idx, item)| {
                let icon = Icon::new(item.icon);
                let title = Text::new(&item.title);
                let mut content = Row::new().spacing(7).padding(5)
                    .push(icon)
                    .push(title);
                // let mut submenu = None;
                if let Some(submenu) = &item.submenu {
                    content = content
                        .push(Space::with_width(Length::Fill))
                        .push(Icon::new(Icons::ArrowRight));
                    // submenu = menu(submenu);
                }
                let mut btn = Button::new(&mut item.state, content)
                    .width(Length::Fill)
                    .on_press(Message::MenuItemSelected(idx));
                if item.selected {
                    btn = btn.style(CustomButton::Selected);
                } else {
                    btn = btn.style(CustomButton::Transparent);
                }

                column.push(btn)
            });
        // let context_menu = menu(&mut self.menu_items);

        Container::new(context_menu)
            .width(Length::Fill)
            .height(Length::Fill)
            .style(ContainerFill(Color::WHITE))
            .into()
    }
}