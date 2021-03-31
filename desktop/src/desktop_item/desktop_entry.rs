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