use std::path::{PathBuf, Path};
use std::fs;
use crate::configs::PersistentData;
use super::desktop_item::DesktopItem;
use super::background::WallpaperItem;
use super::configs::DesktopConf;
use super::errors::DesktopError;
use lazy_static::lazy_static;

const WALLPAPERS_DIR: &str = "wallpapers";
lazy_static! {
    static ref SYS_DIR: PathBuf = PathBuf::from("/usr/share").join(WALLPAPERS_DIR);
    static ref LOCAL_DIR: PathBuf = dirs_next::data_local_dir().unwrap().join(WALLPAPERS_DIR);
    static ref DESK_DIR: PathBuf = dirs_next::desktop_dir().unwrap_or(dirs_next::home_dir().unwrap().join("Desktop"));
}

pub struct DesktopManager {
    desktop_items: Vec<DesktopItem>,
    wallpaper_items: Vec<WallpaperItem>,
    conf: DesktopConf,
}

impl DesktopManager {
    pub fn new() -> Result<Self, DesktopError> {
        let desktop_items: Vec<DesktopItem> = DESK_DIR.read_dir()?.filter_map(|entry| DesktopItem::new(entry.unwrap().path()).ok()).collect();
        let mut wallpaper_items: Vec<WallpaperItem> = Vec::new();
        if SYS_DIR.exists() && SYS_DIR.is_dir() {
            let sys_wallpaper_items = SYS_DIR.read_dir()?.filter_map(|entry| WallpaperItem::from_file(entry.unwrap().path(), false).ok());
            wallpaper_items.extend(sys_wallpaper_items);
        }
        if LOCAL_DIR.exists() && LOCAL_DIR.is_dir() {
            let local_wallpaper_items = LOCAL_DIR.read_dir()?.filter_map(|entry| WallpaperItem::from_file(entry.unwrap().path(), true).ok());
            wallpaper_items.extend(local_wallpaper_items);
        }
        wallpaper_items.sort();

        Ok(Self {
            desktop_items, wallpaper_items,
            conf: DesktopConf::load()?,
        })
    }

    pub fn create_new_folder(&mut self) -> Result<(), DesktopError> {
        let prefix_name = "untitled folder";
        let num_untitled_folders = DESK_DIR.read_dir()?.filter(|entry| {
            let file_name = entry.as_ref().unwrap().file_name(); 
            if let Ok(path_str) = file_name.into_string() {
                path_str.starts_with(prefix_name)
            } else {
                false
            }
        }).count();
        let new_folder = if num_untitled_folders == 0 {
            prefix_name.to_string()
        } else {
            format!("{} {}", prefix_name, num_untitled_folders+1)
        };
        let full_path = DESK_DIR.join(&new_folder);

        fs::create_dir(full_path.to_path_buf())?;
        self.desktop_items.push(DesktopItem::new(full_path)?);

        Ok(())
    }

    pub fn add_wallpaper<P: AsRef<Path>>(&mut self, path: P) -> Result<(), DesktopError> {
        let mut res = false;
        if path.as_ref().exists() && path.as_ref().is_file() {
            if let Some(ext) = path.as_ref().extension() {
                let exts = ext.to_str().unwrap();
                if exts == "png" || exts == "jpg" {
                    if let Some(file_name) = path.as_ref().file_name() {
                        if !LOCAL_DIR.exists() {
                            fs::create_dir_all(LOCAL_DIR.to_path_buf())?;
                        }

                        let local_path = if LOCAL_DIR.join(file_name).exists() {
                            let mut local_path = LOCAL_DIR.join(file_name);
                            if let Some(name) = path.as_ref().file_stem() {
                                local_path = LOCAL_DIR.join(format!("{}-(1)", name.to_str().unwrap())).with_extension(ext);
                            }
        
                            local_path
                        } else {
                            LOCAL_DIR.join(file_name)
                        };

                        fs::copy(path.as_ref(), local_path.to_path_buf())?;
                        self.wallpaper_items.push(WallpaperItem::from_file(local_path.to_path_buf(), true)?);
                        self.conf.background_conf.wallpaper_conf.wallpaper_path = local_path;

                        res = true;
                    }
                }
            }
        } 

        if res {
            Ok(())
        } else {
            Err(DesktopError::PathIsNotAFile(path.as_ref().display().to_string()))
        }
    }

    pub fn config(&self) -> &DesktopConf {
        &self.conf
    }

    pub fn desktop_items(&self) -> &[DesktopItem] {
        self.desktop_items.as_slice()
    }

    pub fn wallpaper_items(&self) -> &[WallpaperItem] {
        self.wallpaper_items.as_slice()
    }
}
