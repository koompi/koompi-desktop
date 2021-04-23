use iced_style::{
    progress_bar::{Style, StyleSheet},
    Background, Color,
};

pub enum ProgressType {
    Default,
}

impl StyleSheet for ProgressType {
    fn style(&self) -> Style {
        match self {
            ProgressType::Default => Style {
                background: Background::Color(Color::BLACK),
                border_radius: 10.0,
                bar: Background::Color(Color::from_rgba8(9, 132, 227, 1.0)),
            },
        }
    }
}
