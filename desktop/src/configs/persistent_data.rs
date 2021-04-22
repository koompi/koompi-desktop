use serde::{de::DeserializeOwned, Serialize};
use std::fs;
use std::path::PathBuf;
use crate::constants::LOCAL_CONF;
use crate::errors::DesktopError;

pub trait PersistentData: DeserializeOwned + Serialize + Default {
    fn relative_path() -> PathBuf;

    fn path() -> Result<PathBuf, DesktopError> {
        let path = LOCAL_CONF.join(Self::relative_path());
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }

        Ok(path)
    }

    fn load() -> Result<Self, DesktopError> {
        let file = Self::path()?;

        if file.exists() { 
            if file.is_file() {
                Ok(toml::from_str(&fs::read_to_string(file)?)?)
            } else {
                Err(DesktopError::ConfigNotFound(file.display().to_string()))
            }
        } else {
            let default = Self::default();
            let toml = toml::to_string_pretty(&default)?;
            fs::write(Self::path()?, toml)?;
            Ok(default)
        } 
    }

    fn save(&self) -> Result<(), DesktopError> {
        let contents = toml::to_string_pretty(&self)?;
        fs::write(Self::path()?, contents)?;

        Ok(())
    }
}