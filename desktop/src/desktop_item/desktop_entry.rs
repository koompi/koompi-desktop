use crate::constants::{EXEC, TRY_EXEC, TERMINAL, HIDDEN, NO_DISPLAY};
use super::desktop_item_error::DesktopItemError;
use subprocess::Exec;
use freedesktop_entry_parser::AttrSelector;

#[derive(Debug, Clone, Default, Eq, Ord, PartialEq, PartialOrd)]
pub struct DesktopEntry {
    try_exec: Option<String>,
    exec: Option<String>,
    pub term: bool,
    pub is_hidden: bool,
    pub no_display: bool,
}

impl DesktopEntry {
    pub fn new(desktop_entry: &AttrSelector<&str>) -> Self {
        let try_exec = desktop_entry.attr(TRY_EXEC).map(ToString::to_string);
        let exec = desktop_entry.attr(EXEC).map(ToString::to_string);
        let term = desktop_entry.attr(TERMINAL).map(|term| term.parse::<bool>().unwrap_or_default()).unwrap_or_default();
        let is_hidden = desktop_entry.attr(HIDDEN).map(|term| term.parse::<bool>().unwrap_or_default()).unwrap_or_default();
        let no_display = desktop_entry.attr(NO_DISPLAY).map(|term| term.parse::<bool>().unwrap_or_default()).unwrap_or_default();

        Self {
            try_exec, exec, term, is_hidden, no_display
        }
    }

    pub fn handle_exec(&self, arg: Option<&str>) -> Result<(), DesktopItemError> {
        let exec_str = if let Some(exec) = &self.try_exec {
            Some(exec)
        } else if let Some(exec) = &self.exec {
            Some(exec)
        } else {
            None
        };

        if let Some(exec_str) = exec_str {
            let re = regex::Regex::new("%.").unwrap();
            let formatted_exec_str = re.replace_all(exec_str, "").to_string();
            let mut splitted_exec_str = formatted_exec_str.trim().split_whitespace();
            let mut cmd = Exec::cmd(splitted_exec_str.next().unwrap());
            while let Some(arg) = splitted_exec_str.next() {
                cmd = cmd.arg(arg);
            }
            if let Some(arg) = arg {
                cmd = cmd.arg(arg);
            }
            if self.term {
                cmd = cmd.arg("&");
            }
            let _ = cmd.detached().join()?;

            Ok(())
        } else {
            Err(DesktopItemError::NoExecString)
        }
    }
}