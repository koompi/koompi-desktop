use iced::{button, container, Background, Color, Vector};

pub const BACKGROUND: Color = Color::from_rgb(238.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0);
pub const FOREGROUND: Color = Color::from_rgb(224.0 / 255.0, 224.0 / 255.0, 224.0 / 255.0);
pub const HOVERED: Color = Color::from_rgb(129.0 / 255.0, 129.0 / 255.0, 129.0 / 255.0);
pub const PRIMARY: Color = Color::from_rgb(12.0 / 255.0, 46.0 / 251.0, 179.0 / 255.0);
pub const SECONDARY: Color = Color::from_rgb(112.0 / 255.0, 16.0 / 251.0, 191.0 / 255.0);
pub const SUCCESS: Color = Color::from_rgb(53.0 / 255.0, 228.0 / 255.0, 138.0 / 255.0);
pub const WARNING: Color = Color::from_rgb(253.0 / 255.0, 202.0 / 255.0, 21.0 / 255.0);
pub const ERROR: Color = Color::from_rgb(251.0 / 255.0, 14.0 / 255.0, 49.0 / 255.0);

pub enum CustomButton {
    Default,
    Primary,
    Secondary,
    Transparent,
    Selected,
    Hovered,
}

impl button::StyleSheet for CustomButton {
    fn active(&self) -> button::Style {
        button::Style {
            text_color: match self {
                CustomButton::Hovered => Color::WHITE,
                CustomButton::Primary => PRIMARY,
                CustomButton::Secondary => SECONDARY,
                CustomButton::Transparent | CustomButton::Selected=> Color::WHITE,
                _ => Color::BLACK,
            },
            background: Some(Background::Color(match self {
                CustomButton::Selected => Color { a: 0.5, ..PRIMARY },
                CustomButton::Transparent => Color::TRANSPARENT,
                CustomButton::Primary => Color { a: 0.3, ..PRIMARY },
                CustomButton::Secondary => Color { a: 0.3, ..SECONDARY },
                CustomButton::Hovered => HOVERED,
                _ => Color::WHITE,
            })),
            border_radius: 7.0,
            border_color: Color::TRANSPARENT,
            border_width: 1.0,
            shadow_offset: match self {
                CustomButton::Default => Vector::new(0.5, 1.0),
                _ => Vector::new(0.0, 0.0)
            },
        }
    }

    fn hovered(&self) -> button::Style {
        let active = self.active();

        match self {
            CustomButton::Transparent => button::Style {
                background: Some(Color { a: 0.3, ..PRIMARY}.into()),
                ..active
            },
            _ => active,
        }
    }
}

pub struct CustomTooltip;
impl container::StyleSheet for CustomTooltip {
    fn style(&self) -> container::Style {
        container::Style {
            text_color: Some(Color::from_rgb8(0xEE, 0xEE, 0xEE)),
            background: Some(Color::from_rgb(0.11, 0.42, 0.87).into()),
            border_radius: 12.0,
            ..container::Style::default()
        }
    }
}