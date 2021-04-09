use super::wallpaper_conf::WallpaperConf;
use de::deserialize_color_hex_string;
use ser::serialize_color_hex;
use serde::{Deserialize, Serialize};
use std::fmt::{self, Display, Formatter};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackgroundConf {
    pub kind: BackgroundType,
    #[serde(
        deserialize_with = "deserialize_color_hex_string",
        serialize_with = "serialize_color_hex"
    )]
    pub color_background: iced_winit::Color,
    #[serde(rename = "Wallpaper_Config")]
    pub wallpaper_conf: WallpaperConf,
}

impl Default for BackgroundConf {
    fn default() -> Self {
        Self {
            kind: BackgroundType::Color,
            color_background: iced_winit::Color::from_rgb8(27, 27, 27),
            wallpaper_conf: WallpaperConf::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BackgroundType {
    Color,
    Wallpaper,
}

impl BackgroundType {
    pub const ALL: [BackgroundType; 2] = [BackgroundType::Color, BackgroundType::Wallpaper];
}

impl Display for BackgroundType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        use BackgroundType::*;
        write!(
            f,
            "{}",
            match self {
                Color => "Color",
                Wallpaper => "Wallpaper",
            }
        )
    }
}

mod ser {
    use iced_winit::Color;
    use serde::ser::Serializer;

    pub(super) fn serialize_color_hex<S>(color: &Color, s: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let red = format!("{:02x}", (color.r * 255.0) as u8);
        let green = format!("{:02x}", (color.g * 255.0) as u8);
        let blue = format!("{:02x}", (color.b * 255.0) as u8);
        s.serialize_str(&format!("#{}{}{}", red, green, blue))
    }
}

mod de {
    use iced_winit::Color;
    use serde::de::{self, Error, Unexpected, Visitor};
    use std::fmt;

    fn hex_to_color(hex: &str) -> Option<Color> {
        if hex.len() == 7 {
            let hash = &hex[0..1];
            let r = u8::from_str_radix(&hex[1..3], 16);
            let g = u8::from_str_radix(&hex[3..5], 16);
            let b = u8::from_str_radix(&hex[5..7], 16);

            return match (hash, r, g, b) {
                ("#", Ok(r), Ok(g), Ok(b)) => Some(Color {
                    r: r as f32 / 255.0,
                    g: g as f32 / 255.0,
                    b: b as f32 / 255.0,
                    a: 1.0,
                }),
                _ => None,
            };
        }

        None
    }

    pub(super) fn deserialize_color_hex_string<'de, D>(deserializer: D) -> Result<Color, D::Error>
    where
        D: de::Deserializer<'de>,
    {
        struct ColorVisitor;

        impl<'de> Visitor<'de> for ColorVisitor {
            type Value = Color;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("a hex string in the format of '#09ACDF'")
            }

            #[allow(clippy::unnecessary_unwrap)]
            fn visit_str<E>(self, s: &str) -> Result<Self::Value, E>
            where
                E: Error,
            {
                if let Some(color) = hex_to_color(s) {
                    return Ok(color);
                }

                Err(de::Error::invalid_value(Unexpected::Str(s), &self))
            }
        }

        deserializer.deserialize_any(ColorVisitor)
    }
}
