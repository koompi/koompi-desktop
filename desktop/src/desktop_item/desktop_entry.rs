use crate::constants::{EXEC, TRY_EXEC, TERMINAL};
use super::desktop_item_error::DesktopItemError;
use subprocess::Exec;
use freedesktop_entry_parser::AttrSelector;

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
        let command = if let Some(exec) = &self.try_exec {
            Some(Exec::cmd(exec))
        } else if let Some(exec) = &self.exec {
            Some(Exec::cmd(exec))
        } else {
            None
        };

        if let Some(mut cmd) = command {
            if !self.term {
                cmd = cmd.arg("&");
            }
            let _ = cmd.detached().communicate()?;
            Ok(())
        } else {
            Err(DesktopItemError::NoExecString)
        }
    }
}