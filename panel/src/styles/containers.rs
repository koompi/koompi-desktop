#![allow(dead_code)]
use iced::{container, Color};

pub const BACKGROUND: Color = Color::from_rgb(238.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0);
pub const FOREGROUND: Color = Color::from_rgb(224.0 / 255.0, 224.0 / 255.0, 224.0 / 255.0);
pub const HOVERED: Color = Color::from_rgb(129.0 / 255.0, 129.0 / 255.0, 129.0 / 255.0);
pub const ACCENT: Color = Color::from_rgb(15.0 / 255.0, 85.0 / 255.0, 179.0 / 255.0);
pub const SUCCESS: Color = Color::from_rgb(31.0 / 255.0, 139.0 / 255.0, 36.0 / 255.0);
pub const WARNING: Color = Color::from_rgb(212.0 / 255.0, 176.0 / 255.0, 17.0 / 255.0);
pub const ERROR: Color = Color::from_rgb(218.0 / 255.0, 16.0 / 255.0, 11.0 / 255.0);

pub enum CustomContainer {
    Background,
    ForegroundWhite,
    ForegroundGray,
    Header,
    Segment,
    FadedBrightForeground,
    Hovered,
    Primary,
    Success,
    Warning,
    Transparent(Color),
}

impl container::StyleSheet for CustomContainer {
    fn style(&self) -> container::Style {
        use CustomContainer::*;
        container::Style {
            background: Some(
                match self {
                    Background | Header => BACKGROUND,
                    ForegroundWhite => Color::WHITE,
                    ForegroundGray | Segment => FOREGROUND,
                    Hovered => Color {
                        a: 0.2,
                        ..Color::BLACK
                    },
                    FadedBrightForeground => Color {
                        a: 0.8,
                        ..FOREGROUND
                    },
                    Primary => Color { a: 0.7, ..ACCENT },
                    Success => SUCCESS,
                    Warning => WARNING,
                    Transparent(color) => Color {
                        a: 0.35,
                        ..(*color)
                    },
                }
                .into(),
            ),
            border_radius: match self {
                Segment => 10.0,
                ForegroundGray | Hovered => 7.0,
                FadedBrightForeground => 4.0,
                Success | Warning | Primary => 5.0,
                _ => 0.0,
            },
            border_width: match self {
                Header | Segment => 1.0,
                Primary => 0.5,
                _ => 0.0,
            },
            border_color: match self {
                Header => Color::TRANSPARENT,
                Primary => Color::BLACK,
                _ => BACKGROUND,
            },
            ..container::Style::default()
        }
    }
}
