use iced::{Font, HorizontalAlignment, Length, Text, VerticalAlignment};
pub fn icon(unicode: char) -> Text {
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
pub fn condition(level: f32) -> Text {
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
fn battery_empty() -> Text {
    icon('\u{f244}')
}
fn battery_quarter() -> Text {
    icon('\u{f243}')
}
fn battery_half() -> Text {
    icon('\u{f242}')
}
fn battery_three_quarter() -> Text {
    icon('\u{f241}')
}
fn battery_full() -> Text {
    icon('\u{f240}')
}

pub fn key() -> Text {
    icon('\u{f084}')
}
pub fn unlock() -> Text {
    icon('\u{f09c}')
}
pub fn wifi() -> Text {
    icon('\u{f1eb}')
}
pub fn search() -> Text {
    icon('\u{f002}')
}

pub fn refresh() -> Text {
    icon('\u{f2f1}')
}
