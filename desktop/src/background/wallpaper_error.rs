use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;

#[derive(Debug, Error)]
pub enum WallpaperError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    IOError(#[from] std::io::Error),
    #[error("not found filename: {name}")]
    NotFound {
        name: String
    },
    #[error("cannot open file")]
    CannotOpen,
    #[error("invalid type of wallpaper", )]
    InvalidType,
}