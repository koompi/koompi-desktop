use iced::{Font, HorizontalAlignment, Length, VerticalAlignment Text};
pub fn icon(unicode: char) -> Text {
    Text::new(&unicode.to_string())
        .font(ICONS)
        .width(Length::Units(14))
        .vertical_alignment(VerticalAlignment::Center)
        .horizontal_alignment(HorizontalAlignment::Center)
        .size(12)
}
const ICONS: Font = Font::External {
    name: "Line Awesome",
    bytes: include_bytes!("../assets/font/la-solid-900.ttf"),
};
