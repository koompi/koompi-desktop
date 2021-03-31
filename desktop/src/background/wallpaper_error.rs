use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;

#[derive(Debug, Error)]
pub enum WallpaperError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IOError(#[from] std::io::Error),
    #[error("this has no image: {0}")]
    NoImage(String),
    #[error("not found filename: {0}")]
    NotFound(String),
    #[error("invalid type of wallpaper", )]
    InvalidType,
}