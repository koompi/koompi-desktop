use std::process::Command;
use std::{fmt, io};
pub trait Connectivity: fmt::Debug {
    fn connect(ssid: String, password: String) -> Result<bool, WifiConnectionError>;
    fn disconnect(ssid: String) -> Result<bool, WifiConnectionError>;
}

pub trait WifiInterface: fmt::Debug {
    /// Check if the wifi interface on host machine is enabled.
    fn is_wifi_enabled() -> Result<bool, WifiError> {
        unimplemented!();
    }

    /// Turn on the wifi interface of host machine.
    fn turn_on() -> Result<(), WifiError> {
        unimplemented!();
    }

    /// Turn off the wifi interface of host machine.
    fn turn_off() -> Result<(), WifiError> {
        unimplemented!();
    }
}

#[derive(Debug)]
pub enum WifiConnectionError {
    /// Adding the newtork profile failed.
    #[cfg(target_os = "windows")]
    AddNetworkProfileFailed,
    /// Failed to connect to wireless network.
    FailedToConnect(String),
    /// Failed to disconnect from wireless network. Try turning the wireless interface down.
    FailedToDisconnect(String),
    /// A wireless error occurred.
    Other { kind: WifiError },
    // SsidNotFound,
}

impl From<io::Error> for WifiConnectionError {
    fn from(error: io::Error) -> Self {
        WifiConnectionError::Other {
            kind: WifiError::IoError(error),
        }
    }
}

#[derive(Debug)]
pub enum WifiError {
    // The specified wifi  is currently disabled. Try switching it on.
    WifiDisabled,
    /// The wifi interface interface failed to switch on.
    #[cfg(target_os = "windows")]
    InterfaceFailedToOn,
    /// IO Error occurred.
    IoError(io::Error),
}
#[derive(Debug, Clone, Default)]
pub struct Wifi;
impl WifiInterface for Wifi {
    fn is_wifi_enabled() -> Result<bool, WifiError> {
        let output = Command::new("nmcli")
            .args(&["radio", "wifi"])
            .output()
            .map_err(|err| WifiError::IoError(err))?;

        Ok(String::from_utf8_lossy(&output.stdout)
            .replace(" ", "")
            .replace("\n", "")
            .contains("enabled"))
    }
    fn turn_on() -> Result<(), WifiError> {
        Command::new("nmcli")
            .args(&["radio", "wifi", "on"])
            .output()
            .map_err(|err| WifiError::IoError(err))?;

        Ok(())
    }
    fn turn_off() -> Result<(), WifiError> {
        Command::new("nmcli")
            .args(&["radio", "wifi", "off"])
            .output()
            .map_err(|err| WifiError::IoError(err))?;

        Ok(())
    }
}
impl Connectivity for Wifi {
    fn connect(ssid: String, password: String) -> Result<bool, WifiConnectionError> {
        if !Wifi::is_wifi_enabled().map_err(|err| WifiConnectionError::Other { kind: err })? {
            return Err(WifiConnectionError::Other {
                kind: WifiError::WifiDisabled,
            });
        }
        let output = Command::new("nmcli")
            .args(&["d", "wifi", "connect", &ssid, "password", &password])
            .output()
            .map_err(|err| WifiConnectionError::FailedToConnect(format!("{}", err)))?;
        if !String::from_utf8_lossy(&output.stdout)
            .as_ref()
            .contains("successfully activated")
        {
            Ok(false)
        } else {
            Ok(true)
        }
    }
    fn disconnect(ssid: String) -> Result<bool, WifiConnectionError> {
        let output = Command::new("nmcli")
            .args(&["connection", "down", &ssid])
            .output()
            .map_err(|err| WifiConnectionError::FailedToDisconnect(format!("{}", err)))?;
        if !String::from_utf8_lossy(&output.stdout)
            .as_ref()
            .contains("successfully deactivated")
        {
            Ok(false)
        } else {
            Ok(true)
        }
    }
}
