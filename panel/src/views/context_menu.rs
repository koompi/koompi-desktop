use iced::time;
use iced_wgpu::Renderer;
use iced_winit::{
    application::Application, button, Button, Column, Command, Container, Element, Program,
    Subscription, Text,
};
#[derive(Debug)]
pub struct ContexMenu {
    categories: Position,
    show_pos: button::State,
    counter: usize,
    now: chrono::DateTime<chrono::Local>,
}

#[derive(Debug, Clone)]
pub enum ContextMenuMsg {
    OnShowMen,
    Tick(chrono::DateTime<chrono::Local>),
}
impl Application for ContexMenu {
    type Flags = ();

    fn new(_flags: ()) -> (Self, Command<ContextMenuMsg>) {
        println!("applicaiton launcher");
        (
            Self {
                categories: Position::Top,
                show_pos: button::State::new(),
                counter: 0,
                now: chrono::Local::now(),
            },
            Command::none(),
        )
    }
    fn title(&self) -> String {
        String::from("Context Menu")
    }
    fn subscription(&self) -> Subscription<ContextMenuMsg> {
        time::every(std::time::Duration::from_millis(500))
            .map(|_| ContextMenuMsg::Tick(chrono::Local::now()))
    }
}
impl Program for ContexMenu {
    type Renderer = Renderer;
    type Message = ContextMenuMsg;
    fn update(&mut self, message: ContextMenuMsg) -> Command<ContextMenuMsg> {
        match message {
            ContextMenuMsg::OnShowMen => {
                self.counter += 1;
                println!("Click me : {}", self.counter);
            }
            ContextMenuMsg::Tick(local_time) => {
                let now = local_time;
                if now != self.now {
                    self.now = now;
                }
                println!("current time: {:?}", self.now);
            }
        }
        Command::none()
    }

    fn view(&mut self) -> Element<ContextMenuMsg, Renderer> {
        Container::new(
            Column::new()
                .push(Text::new(self.counter.to_string()))
                .push(
                    Button::new(&mut self.show_pos, Text::new(self.now.time().to_string()))
                        .on_press(ContextMenuMsg::OnShowMen),
                ),
        )
        .into()
    }
}
#[derive(Debug)]
pub enum Position {
    Top,
    Left,
    Rigth,
    Bottom,
}
