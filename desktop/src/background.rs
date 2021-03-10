mod placement;
mod thumbnail;
mod thumbnail_size;
pub mod wallpaper_type;

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::io::{Error, ErrorKind};
use std::fs;

#[derive(Debug, Serialize, Deserialize)]
pub struct Background {
    wallpaper_path: PathBuf,
    primary_color: String,
    secondary_color: String,
    is_enabled: bool,
}

impl Background {
    pub fn from_config<P: AsRef<Path>>(file: P) -> Result<Self, Error> {
        match toml::from_str(&fs::read_to_string(file)?) {
            Ok(background) => Ok(background),
            Err(err) => Err(Error::new(ErrorKind::Other, err))
        }
    }

    pub fn set_wallpaper<P: AsRef<Path>>(&mut self, file: P) {
        self.wallpaper_path = file.as_ref().to_path_buf();
    }

    pub fn wallpaper_path(&self) -> &PathBuf {
        &self.wallpaper_path
    }

    pub fn draw(&self) {

    }
}