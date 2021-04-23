use iced_wgpu::Renderer;
use iced_winit::{Font, HorizontalAlignment, Length, Text, VerticalAlignment};
type SText = Text<Renderer>;
pub fn icon(unicode: char) -> SText {
    Text::new(&unicode.to_string())
        .font(ICONS)
        .width(Length::Units(16))
        .vertical_alignment(VerticalAlignment::Center)
        .horizontal_alignment(HorizontalAlignment::Center)
        .size(18)
}
const ICONS: Font = Font::External {
    name: "Line Awesome",
    bytes: include_bytes!("../assets/font/la-solid-900.ttf"),
};
pub fn condition(level: f32) -> SText {
    let to_i32 = level as i32;
    match to_i32 {
        0..=10 => battery_full(),
        11..=30 => battery_quarter(),
        31..=50 => battery_half(),
        51..=80 => battery_three_quarter(),
        81..=100 => battery_full(),
        _ => battery_empty(),
    }
}
fn battery_empty() -> SText {
    icon('\u{f244}')
}
fn battery_quarter() -> SText {
    icon('\u{f243}')
}
fn battery_half() -> SText {
    icon('\u{f242}')
}
fn battery_three_quarter() -> SText {
    icon('\u{f241}')
}
fn battery_full() -> SText {
    icon('\u{f240}')
}

pub fn key() -> SText {
    icon('\u{f084}')
}
pub fn unlock() -> SText {
    icon('\u{f09c}')
}
pub fn wifi() -> SText {
    icon('\u{f1eb}')
}
pub fn search() -> SText {
    icon('\u{f002}')
}

pub fn refresh() -> SText {
    icon('\u{f2f1}')
}
