use failure::Error;
use freedesktop_entry_parser::errors::ParseError;

#[derive(Debug, Fail)]
pub enum DesktopItemError {
    #[fail(display = "parse error")]
    ParseError(ParseError),
    #[fail(display = "invalid filename: {}", name)]
    NoFilename {
        name: String
    },
    #[fail(display = "unknown encoding of the file")]
    UnknownEncoding,
    #[fail(display = "cannot open file")]
    CannotOpen,
    #[fail(display = "cannot launch due to no execute string")]
    NoExecString,
    #[fail(display = "cannot launch due to bad execute string")]
    BadExecString,
    #[fail(display = "not a launchable type")]
    NotLaunchable,
    #[fail(display = "invalid type of application", )]
    InvalidType,
}