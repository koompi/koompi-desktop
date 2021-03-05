use iced_wgpu::Renderer;
use iced_winit::{
   Color, Command, Element, Length, Program, Container, Row,
};

pub struct Desktop {
   background_color: Color,
}

#[derive(Debug, Clone)]
pub enum Message {
   BackgroundColorChanged(Color),
}

impl Desktop {
   pub fn new() -> Desktop {
      Desktop {
         background_color: Color::from_rgb8(34,58,94),
      }
   }

   pub fn background_color(&self) -> Color {
      self.background_color
   }
}

impl Program for Desktop {
   type Renderer = Renderer;
   type Message = Message;

   fn update(&mut self, message: Message) -> Command<Message> {
      match message {
         Message::BackgroundColorChanged(color) => {
            self.background_color = color;
         }
      }

      Command::none()
   }

   fn view(&mut self) -> Element<Message, Renderer> {
      Container::new(Row::new())
         .width(Length::Fill)
         .height(Length::Fill)
         .into()
   }
}
