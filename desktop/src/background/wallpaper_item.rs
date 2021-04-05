use std::path::{PathBuf, Path};
use super::wallpaper_error::WallpaperError;
use crate::constants::{DESKTOP_ENTRY, NAME};
use std::cmp::Ordering;
const METADATA_FILE: &str = "metadata.desktop";

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

                    Ok(Self {
                        is_local, name, path: path.to_path_buf()
                    })

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

    pub fn load_image(&self, size: (u32, u32)) -> PathBuf {
        if self.path.is_file() {
            self.path.to_path_buf()
        } else {
            let contents_path = self.path.join("contents");
            let images_path = contents_path.join("images");
            let image_path = images_path.join(format!("{}x{}", size.0, size.1)).with_extension("jpg");
            if image_path.exists() {
                image_path.to_path_buf()
            } else if image_path.with_extension("png").exists() {
                image_path.with_extension("png").to_path_buf()
            } else {
                let mut screenshot = contents_path.join("screenshot").with_extension("png");
                if !screenshot.exists() {
                    screenshot = screenshot.with_extension("jpg");
                }
                screenshot
                // walkdir::WalkDir::new(images_path).follow_links(true).into_iter().filter_map(|e| e.ok())
                //     .filter_map(|entry| if entry.path().is_file() {
                //         Some(entry.path().to_path_buf())
                //     } else {
                //         None
                //     })
                //     .nth(0)
                //     .unwrap_or(screenshot)
            }
        }
    }
}

impl Ord for WallpaperItem {
    fn cmp(&self, other: &Self) -> Ordering {
        self.name.cmp(&other.name)
    }
}