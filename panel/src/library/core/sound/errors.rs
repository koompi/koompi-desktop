use libpulse_binding as pulse;
use pulse::error::PAErr;
use std::fmt;

impl From<PAErr> for PulseCtlError {
    fn from(error: PAErr) -> Self {
        PulseCtlError {
            error: PulseCtlErrorType::PulseAudioError,
            message: format!("PulseAudio returned error code {}", error.0),
        }
    }
}

impl fmt::Debug for PulseCtlError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let mut error_string = String::new();
        match self.error {
            PulseCtlErrorType::ConnectError => {
                error_string.push_str("ConnectError");
            }
            PulseCtlErrorType::OperationError => {
                error_string.push_str("OperationError");
            }
            PulseCtlErrorType::PulseAudioError => {
                error_string.push_str("PulseAudioError");
            }
        }
        write!(f, "[{}]: {}", error_string, self.message)
    }
}

pub(crate) enum PulseCtlErrorType {
    ConnectError,
    OperationError,
    PulseAudioError,
}

/// Error thrown when PulseAudio throws an error code, there are 3 variants
/// `PulseCtlErrorType::ConnectError` when there's an error establishing a connection
/// `PulseCtlErrorType::OperationError` when the requested operation quis unexpecdatly or is cancelled
/// `PulseCtlErrorType::PulseAudioError` when PulseAudio returns an error code in any circumstance
pub struct PulseCtlError {
    error: PulseCtlErrorType,
    message: String,
}

impl PulseCtlError {
    pub(crate) fn new(err: PulseCtlErrorType, msg: &str) -> Self {
        PulseCtlError {
            error: err,
            message: msg.to_string(),
        }
    }
}

impl From<PulseCtlError> for ControllerError {
    fn from(error: super::errors::PulseCtlError) -> Self {
        ControllerError {
            error: ControllerErrorType::PulseCtlError,
            message: format!("{:?}", error),
        }
    }
}

impl fmt::Debug for ControllerError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let mut error_string = String::new();
        match self.error {
            ControllerErrorType::PulseCtlError => {
                error_string.push_str("PulseCtlError");
            }
            ControllerErrorType::GetInfoError => {
                error_string.push_str("GetInfoError");
            }
        }
        write!(f, "[{}]: {}", error_string, self.message)
    }
}

pub(crate) enum ControllerErrorType {
    PulseCtlError,
    GetInfoError,
}

/// Error thrown while fetching data from pulseaudio,
/// has two variants: PulseCtlError for when PulseAudio returns an error code
/// and GetInfoError when a request for data fails for whatever reason
pub struct ControllerError {
    error: ControllerErrorType,
    message: String,
}

impl ControllerError {
    pub(crate) fn new(err: ControllerErrorType, msg: &str) -> Self {
        ControllerError {
            error: err,
            message: msg.to_string(),
        }
    }
}
