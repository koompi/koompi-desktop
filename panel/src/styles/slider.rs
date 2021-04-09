use iced::{
    slider::{Handle, HandleShape, Style, StyleSheet},
    Background, Color,
};

pub enum SliderType {
    Default,
}
impl StyleSheet for SliderType {
    fn active(&self) -> Style {
        Style {
            rail_colors: ([0.6, 0.6, 0.6, 0.5].into(), Color::WHITE),
            handle: Handle {
                shape: HandleShape::Circle { radius: 8.0 },
                color: Color::from_rgb(0.95, 0.95, 0.95),
                border_color: Color::from_rgb(0.6, 0.6, 0.6),
                border_width: 10.0,
            },
        }
    }
    fn hovered(&self) -> Style {
        let active = self.active();
        Style {
            handle: Handle {
                color: Color::from_rgb(0.90, 0.90, 0.90),
                ..active.handle
            },
            ..active
        }
    }
    fn dragging(&self) -> Style {
        let active = self.active();
        Style {
            handle: Handle {
                color: Color::from_rgb(0.85, 0.85, 0.85),
                ..active.handle
            },
            ..active
        }
    }
}
