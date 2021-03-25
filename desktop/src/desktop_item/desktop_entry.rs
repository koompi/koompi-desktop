use std::process::Command;
use super::desktop_item_error::DesktopItemError;
use freedesktop_entry_parser::AttrSelector;
use crate::constants::{EXEC, TRY_EXEC, TERMINAL};

#[derive(Debug, Clone, Default)]
pub struct DesktopEntry {
    exec: Option<String>,
    try_exec: Option<String>,
    term: bool,
}

impl DesktopEntry {
    pub fn new(desktop_entry: &AttrSelector<&str>) -> Self {
        let exec = desktop_entry.attr(EXEC).map(ToString::to_string);
        let try_exec = desktop_entry.attr(TRY_EXEC).map(ToString::to_string);
        let term = desktop_entry.attr(TERMINAL).map(|term| term.parse::<bool>().unwrap_or(false)).unwrap_or(false);

        Self {
            exec, try_exec, term
        }
    }

    pub fn handle_exec(&self) -> Result<(), DesktopItemError> {
        let mut command = if let Some(exec) = &self.try_exec {
            Some(Command::new(exec))
        } else if let Some(exec) = &self.exec {
            Some(Command::new(exec))
        } else {
            None
        };

        if let Some(cmd) = &mut command {
            if !self.term {
                cmd.arg("&");
            }
            cmd.spawn().or(Err(DesktopItemError::BadExecString))?;
            Ok(())
        } else {
            Err(DesktopItemError::NoExecString)
        }
    }
}