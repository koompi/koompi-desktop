use std::path::{PathBuf, Path};
use super::wallpaper_error::WallpaperError;
use crate::constants::{DESKTOP_ENTRY, NAME};
use std::cmp::Ordering;
const METADATA_FILE: &str = "metadata.desktop";
const SCREENSHOT_FILE: &str = "screenshot";

#[derive(Debug, Clone, Default, PartialEq, PartialOrd, Eq)]
pub struct WallpaperItem {
    pub name: Option<String>,
    pub is_local: bool,
    pub path: PathBuf,
}

impl WallpaperItem {
    pub fn from_file<P: AsRef<Path>>(path: P, is_local: bool) -> Result<Self, WallpaperError> {
        let path = path.as_ref();
        if path.exists() {
            if path.is_file() {
                Ok(Self {
                    is_local,
                    path: path.to_path_buf(),
                    name: path.file_stem().map(|name| name.to_str().unwrap().to_string()),
                })
            } else if path.is_dir() {
                let metadata = path.join(METADATA_FILE);
                if metadata.exists() {
                    let entry = freedesktop_entry_parser::parse_entry(metadata)?;
                    let desktop_entry = entry.section(DESKTOP_ENTRY);
                    let name = desktop_entry.attr(NAME).map(ToString::to_string);
                    let image_path = path.join("contents").join(SCREENSHOT_FILE);
                    let image_file = if image_path.with_extension("png").exists() {
                        Some(image_path.with_extension("png"))
                    } else if image_path.with_extension("jpg").exists() {
                        Some(image_path.with_extension("jpg"))
                    } else {
                        None
                    };

                    if let Some(path) = image_file {
                        Ok(Self {
                            is_local, name, path
                        })
                    } else {
                        Err(WallpaperError::NoImage(path.display().to_string()))
                    }

                } else {
                    Err(WallpaperError::NotFound(path.display().to_string()))
                }
            } else {
                Err(WallpaperError::InvalidType)
            }
        } else {
            Err(WallpaperError::NotFound(path.display().to_string()))
        }
    }
}

impl Ord for WallpaperItem {
    fn cmp(&self, other: &Self) -> Ordering {
        self.name.cmp(&other.name)
    }
}