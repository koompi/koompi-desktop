use std::path::{PathBuf, Path};
use super::wallpaper_error::WallpaperError;
use crate::constants::{DESKTOP_ENTRY, NAME};
use std::cmp::Ordering;
const METADATA_FILE: &str = "metadata.desktop";
const SCREENSHOT_FILE: &str = "screenshot.jpg";

#[derive(Debug, Clone, Default, PartialEq, PartialOrd, Eq)]
pub struct WallpaperItem {
    pub name: Option<String>,
    pub is_local: bool,
    pub path: PathBuf,
}

impl WallpaperItem {
    pub fn from_file<P: AsRef<Path>>(file: P, is_local: bool) -> Result<Self, WallpaperError> {
        let file = file.as_ref();
        if file.exists() {
            if file.is_file() {
                Ok(Self {
                    is_local,
                    path: file.to_path_buf(),
                    name: file.file_stem().map(|name| name.to_str().unwrap().to_string()),
                })
            } else if file.is_dir() {
                let metadata = file.join(METADATA_FILE);
                if metadata.exists() {
                    let entry = freedesktop_entry_parser::parse_entry(metadata)?;
                    let desktop_entry = entry.section(DESKTOP_ENTRY);
                    let name = desktop_entry.attr(NAME).map(ToString::to_string);

                    Ok(Self {
                        is_local, name,
                        path: file.join("contents").join(SCREENSHOT_FILE)
                    })
                } else {
                    Err(WallpaperError::NotFound{name: file.display().to_string()})
                }
            } else {
                Err(WallpaperError::InvalidType)
            }
        } else {
            Err(WallpaperError::NotFound{name: file.display().to_string()})
        }
    }
}

impl Ord for WallpaperItem {
    fn cmp(&self, other: &Self) -> Ordering {
        self.name.cmp(&other.name)
    }
}