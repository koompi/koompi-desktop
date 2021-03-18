use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;

#[derive(Debug, Error)]
pub enum DesktopItemError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error("invalid filename: {name}")]
    NoFilename {
        name: String
    },
    #[error("cannot open file")]
    CannotOpen,
    #[error("cannot launch due to no execute string")]
    NoExecString,
    #[error("cannot launch due to bad execute string")]
    BadExecString,
    #[error("not a launchable type")]
    NotLaunchable,
    #[error("invalid type of application", )]
    InvalidType,
    #[error(transparent)]
    IOError(#[from] std::io::Error),
}