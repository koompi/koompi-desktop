use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;

#[derive(Debug, Error)]
pub enum WallpaperError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IOError(#[from] std::io::Error),
    #[error("this has no image: {0}")]
    NotFound(String),
    #[error("invalid type of wallpaper", )]
    InvalidType,
}