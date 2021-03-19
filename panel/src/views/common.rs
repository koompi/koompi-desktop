use iced::{Font, HorizontalAlignment, Length, Text};
pub fn icon(unicode: char) -> Text {
    Text::new(&unicode.to_string())
        .font(ICONS)
        .width(Length::Units(20))
        .horizontal_alignment(HorizontalAlignment::Center)
        .size(20)
}
const ICONS: Font = Font::External {
    name: "Line Awesome",
    bytes: include_bytes!("../assets/font/la-solid-900.ttf"),
};
