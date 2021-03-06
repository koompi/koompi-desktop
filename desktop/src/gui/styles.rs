use iced::{button, container, slider, checkbox, pick_list, Color, Vector};

pub const BACKGROUND: Color = Color::from_rgb(238.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0);
pub const FOREGROUND: Color = Color::from_rgb(224.0 / 255.0, 224.0 / 255.0, 224.0 / 255.0);
pub const HOVERED: Color = Color::from_rgb(66.0 / 255.0, 66.0 / 255.0, 66.0 / 255.0);
pub const PRIMARY: Color = Color::from_rgb(12.0 / 255.0, 46.0 / 251.0, 179.0 / 255.0);
pub const SECONDARY: Color = Color::from_rgb(112.0 / 255.0, 16.0 / 251.0, 191.0 / 255.0);
// pub const SUCCESS: Color = Color::from_rgb(53.0 / 255.0, 228.0 / 255.0, 138.0 / 255.0);
// pub const WARNING: Color = Color::from_rgb(253.0 / 255.0, 202.0 / 255.0, 21.0 / 255.0);
// pub const ERROR: Color = Color::from_rgb(251.0 / 255.0, 14.0 / 255.0, 49.0 / 255.0);

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
        use CustomButton::*;
        button::Style {
            text_color: match self {
                Primary => PRIMARY,
                Secondary => SECONDARY,
                Transparent | Selected => Color::WHITE,
                _ => Color::BLACK,
            },
            background: Some(
                match self {
                    Default => Color::WHITE,
                    Selected => Color { a: 0.5, ..PRIMARY },
                    Primary => Color { a: 0.3, ..PRIMARY },
                    Secondary => Color {
                        a: 0.3,
                        ..SECONDARY
                    },
                    Hovered => Color { a: 0.3, ..HOVERED },
                    _ => Color::TRANSPARENT,
                }
                .into(),
            ),
            border_radius: 7.0,
            border_color: Color::TRANSPARENT,
            border_width: 1.0,
            shadow_offset: match self {
                Default => Vector::new(0.5, 0.5),
                _ => Vector::new(0.0, 0.0)
            },
        }
    }

    fn hovered(&self) -> button::Style {
        use CustomButton::*;
        let active = self.active();

        button::Style {
            background: match self {
                Transparent => Some(Color { a: 0.3, ..PRIMARY }.into()),
                Text => Some(Color { a: 0.3, ..HOVERED }.into()),
                Primary | Secondary | Hovered => Some(active.text_color.into()),
                _ => active.background,
            },
            text_color: match self {
                Primary | Secondary | Hovered => Color::WHITE,
                _ => active.text_color,
            },
            ..active
        }
    }
}

pub enum CustomContainer {
    // Background,
    Foreground,
    // Primary,
    // Secondary,
    // Success,
    // Warning,
    // Error,
    // Hovered,
}
impl container::StyleSheet for CustomContainer {
    fn style(&self) -> container::Style {
        use CustomContainer::*;
        container::Style {
            background: Some(match self {
                // Background => BACKGROUND,
                Foreground => FOREGROUND,
                // Primary => PRIMARY,
                // Secondary => SECONDARY,
                // Success => SUCCESS,
                // Warning => WARNING,
                // Error => ERROR,
                // Hovered => HOVERED
            }.into()),
            border_radius: 7.0,
            ..container::Style::default()
        }
    }
}


pub struct CustomSelect;
impl pick_list::StyleSheet for CustomSelect {
    fn menu(&self) -> iced_style::menu::Style {
        let default = Default::default();

        iced_style::menu::Style {
            selected_background: PRIMARY.into(),
            ..default
        }
    }

    fn active(&self) -> pick_list::Style {
        pick_list::Style {
            text_color: Color::BLACK,
            background: Color { a: 0.3, ..PRIMARY }.into(),
            icon_size: 0.5,
            border_color: PRIMARY,
            border_radius: 5.0,
            border_width: 0.0,
        }
    }

    fn hovered(&self) -> pick_list::Style {
        self.active()
    }
}

pub struct CustomSlider;
impl slider::StyleSheet for CustomSlider {
    fn active(&self) -> slider::Style {
        slider::Style {
            rail_colors: (Color{ a: 0.5, ..HOVERED }, Color::TRANSPARENT),
            handle: slider::Handle {
                shape: slider::HandleShape::Circle { radius: 9.0 },
                color: PRIMARY,
                border_width: 0.0,
                border_color: Color::TRANSPARENT,
            },
        }
    }

    fn hovered(&self) -> slider::Style {
        self.active()
    }

    fn dragging(&self) -> slider::Style {
        self.hovered()
    }
}

pub struct CustomCheckbox;
impl checkbox::StyleSheet for CustomCheckbox {
    fn active(&self, is_checked: bool) -> checkbox::Style {
        checkbox::Style {
            background: if is_checked { PRIMARY } else { Color::WHITE }.into(),
            checkmark_color: Color::WHITE,
            border_radius: 5.0,
            border_width: 1.5,
            border_color: if is_checked { PRIMARY } else { HOVERED }.into(),
        }
    }

    fn hovered(&self, is_checked: bool) -> checkbox::Style {
        self.active(is_checked)
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
