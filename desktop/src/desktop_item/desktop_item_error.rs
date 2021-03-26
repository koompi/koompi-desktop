use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;
use subprocess::PopenError;

#[derive(Debug, Error)]
pub enum DesktopItemError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    PopenError(#[from] PopenError),
    #[error("invalid filename: {name}")]
    NoFilename {
        name: String
    },
    #[error("cannot launch due to no execute string")]
    NoExecString,
    // #[error("cannot launch due to bad execute string")]
    // BadExecString,
    #[error("invalid type of application", )]
    InvalidType,
    #[error(transparent)]
    IOError(#[from] std::io::Error),
}