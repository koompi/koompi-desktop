use thiserror::Error;
use freedesktop_entry_parser::errors::ParseError;
use subprocess::PopenError;

#[derive(Debug, Error)]
pub enum DesktopItemError {
    #[error(transparent)]
    ParseError(#[from] ParseError),
    #[error(transparent)]
    PopenError(#[from] PopenError),
    #[error("invalid filename: {0}")]
    NoFilename(String),
    #[error("cannot launch due to no execute string")]
    NoExecString,
    #[error("bad handle launch execute")]
    BadHandleExec,
    #[error("no default application to execute")]
    NoDefaultExec,
    #[error("invalid type of desktop item", )]
    InvalidType,
    #[error(transparent)]
    IOError(#[from] std::io::Error),
}