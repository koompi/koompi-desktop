use iced::{button, container, Color, Vector};

pub const BACKGROUND: Color = Color::from_rgb(238.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0);
pub const FOREGROUND: Color = Color::from_rgb(224.0 / 255.0, 224.0 / 255.0, 224.0 / 255.0);
pub const HOVERED: Color = Color::from_rgb(66.0 / 255.0, 66.0 / 255.0, 66.0 / 255.0);
pub const PRIMARY: Color = Color::from_rgb(12.0 / 255.0, 46.0 / 251.0, 179.0 / 255.0);
pub const SECONDARY: Color = Color::from_rgb(112.0 / 255.0, 16.0 / 251.0, 191.0 / 255.0);
pub const SUCCESS: Color = Color::from_rgb(53.0 / 255.0, 228.0 / 255.0, 138.0 / 255.0);
pub const WARNING: Color = Color::from_rgb(253.0 / 255.0, 202.0 / 255.0, 21.0 / 255.0);
pub const ERROR: Color = Color::from_rgb(251.0 / 255.0, 14.0 / 255.0, 49.0 / 255.0);

pub enum CustomButton {
    Default,
    Text,
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
                CustomButton::Primary => PRIMARY,
                CustomButton::Secondary => SECONDARY,
                CustomButton::Transparent | CustomButton::Selected => Color::WHITE,
                _ => Color::BLACK,
            },
            background: Some(match self {
                CustomButton::Default => Color::WHITE,
                CustomButton::Selected => Color { a: 0.5, ..PRIMARY },
                CustomButton::Primary => Color { a: 0.3, ..PRIMARY },
                CustomButton::Secondary => Color { a: 0.3, ..SECONDARY },
                CustomButton::Hovered => Color { a: 0.3, ..HOVERED },
                _ => Color::TRANSPARENT,
            }.into()),
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

        button::Style {
            background: match self {
                CustomButton::Transparent => Some(Color { a: 0.3, ..PRIMARY}.into()),
                CustomButton::Text => Some(Color { a: 0.3, ..HOVERED }.into()),
                _ => active.background
            },
            ..active
        }
    }
}

pub struct CustomTooltip;
impl container::StyleSheet for CustomTooltip {
    fn style(&self) -> container::Style {
        container::Style {
            background: Some(Color::WHITE.into()),
            ..container::Style::default()
        }
    }
}

pub struct ContainerFill(pub Color);
impl container::StyleSheet for ContainerFill {
    fn style(&self) -> container::Style {
        container::Style {
            background: Some(self.0.into()),
            ..container::Style::default()
        }
    }
}